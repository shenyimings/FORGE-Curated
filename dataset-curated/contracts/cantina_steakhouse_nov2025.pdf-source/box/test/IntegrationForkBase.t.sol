// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Box} from "../src/Box.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IBox} from "../src/interfaces/IBox.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";
import {VaultV2} from "@vault-v2/src/VaultV2.sol";
import {MorphoVaultV1Adapter} from "@vault-v2/src/adapters/MorphoVaultV1Adapter.sol";

import {IBoxAdapter} from "../src/interfaces/IBoxAdapter.sol";
import {IBoxAdapterFactory} from "../src/interfaces/IBoxAdapterFactory.sol";
import {BoxAdapterFactory} from "../src/factories/BoxAdapterFactory.sol";
import {BoxAdapterCachedFactory} from "../src/factories/BoxAdapterCachedFactory.sol";
import {BoxAdapter} from "../src/BoxAdapter.sol";
import {BoxAdapterCached} from "../src/BoxAdapterCached.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {VaultV2Lib} from "../src/periphery/VaultV2Lib.sol";
import {BoxLib} from "../src/periphery/BoxLib.sol";

import {FundingMorpho} from "../src/FundingMorpho.sol";
import {FundingAave, IPool} from "../src/FundingAave.sol";
import {MarketParams, IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {FlashLoanMorpho} from "../src/periphery/FlashLoanMorpho.sol";
import {IFunding} from "../src/interfaces/IFunding.sol";
import {MorphoVaultV1AdapterLib} from "../src/periphery/MorphoVaultV1AdapterLib.sol";
import "../src/libraries/Constants.sol";

/// @notice Minimal WETH interface for testing
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/// @notice Minimal Aave v3 Addresses Provider to obtain the Pool
interface IPoolAddressesProvider {
    function getPool() external view returns (address);
}

contract TestableVaultV2 is VaultV2 {
    constructor(address owner, address asset) VaultV2(owner, asset) {}

    function resetFirstTotalAssets() external {
        firstTotalAssets = uint256(0);
    }
}

/**
 * @title Peaty on Base integration test
 */
contract IntegrationForkBaseTest is Test {
    using BoxLib for Box;
    using VaultV2Lib for TestableVaultV2;
    using MorphoVaultV1AdapterLib for MorphoVaultV1Adapter;

    TestableVaultV2 vault;
    Box box1; // Will hold stUSD
    Box box1b; // Will hold stUSD but with a cached adapter
    Box box2; // Will hold a PT with a cached adapter
    IBoxAdapter adapter1;
    BoxAdapterCached adapter1b;
    BoxAdapterCached adapter2;
    MorphoVaultV1Adapter bbqusdcAdapter;

    address owner = address(0x1);
    address curator = address(0x2);
    address guardian = address(0x3);
    address allocator = address(0x4);
    address user = address(0x5);

    IERC20 usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    IERC4626 bbqusdc = IERC4626(0xBeeFa74640a5f7c28966cbA82466EED5609444E0); // bbqUSDC on Base

    IERC4626 stusd = IERC4626(0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776);
    IOracle stusdOracle = IOracle(0x2eede25066af6f5F2dfc695719dB239509f69915);

    IERC20 ptusr25sep = IERC20(0xa6F0A4D18B6f6DdD408936e81b7b3A8BEFA18e77);
    IOracle ptusr25sepOracle = IOracle(0x6AdeD60f115bD6244ff4be46f84149bA758D9085);

    ISwapper swapper = ISwapper(0x5C9dA86ECF5B35C8BF700a31a51d8a63fA53d1f6);

    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    address irm = 0x46415998764C29aB2a25CbeA6254146D50D22687;

    IBoxAdapterFactory boxAdapterFactory;
    IBoxAdapterFactory boxAdapterCachedFactory;

    /// @notice Will setup Peaty Base investing in bbqUSDC, box1 (stUSD) and box2 (PTs)
    function setUp() public {
        // Fork base on a recent block (December 2024)
        // Note: Using a recent block to ensure Aave V3 is deployed
        uint256 forkId = vm.createFork(vm.rpcUrl("base"), 34194011); // Use latest block
        vm.selectFork(forkId);

        boxAdapterFactory = new BoxAdapterFactory();
        boxAdapterCachedFactory = new BoxAdapterCachedFactory();

        vault = new TestableVaultV2(address(owner), address(usdc));

        vm.startPrank(owner);
        vault.setCurator(address(curator));
        vault.setIsSentinel(address(guardian), true);
        vm.stopPrank();

        vm.startPrank(curator);
        vault.addAllocatorInstant(address(allocator));
        vm.stopPrank();

        // Setting the vault to use bbqUSDC as the asset
        bbqusdcAdapter = new MorphoVaultV1Adapter(address(vault), address(bbqusdc));

        vm.startPrank(curator);
        vault.addCollateralInstant(address(bbqusdcAdapter), bbqusdcAdapter.data(), 1_000_000 * 10 ** 6, 1 ether); // 1,000,000 USDC absolute cap and 100% relative cap
        vm.stopPrank();

        vm.startPrank(allocator);
        vault.setLiquidityAdapterAndData(address(bbqusdcAdapter), "");
        vm.stopPrank();

        // Creating Box 1 which will invest in stUSD
        string memory name = "Box 1";
        string memory symbol = "BOX1";
        uint256 maxSlippage = 0.01 ether; // 1%
        uint256 slippageEpochDuration = 7 days;
        uint256 shutdownSlippageDuration = 10 days;
        box1 = new Box(
            address(usdc),
            owner,
            curator,
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            MAX_SHUTDOWN_WARMUP
        );

        // Creating the ERC4626 adapter between the vault and box1
        adapter1 = boxAdapterFactory.createBoxAdapter(address(vault), box1);

        // Allow box 1 to invest in stUSD
        vm.startPrank(curator);
        box1.setGuardianInstant(guardian);
        box1.addTokenInstant(stusd, stusdOracle);
        box1.setIsAllocator(address(allocator), true);
        box1.addFeederInstant(address(adapter1));
        vault.addCollateralInstant(address(adapter1), adapter1.adapterData(), 1_000_000 * 10 ** 6, 1 ether); // 1,000,000 USDC absolute cap and 50% relative cap
        vm.stopPrank();

        // Creating Box 2 which will invest in PT-USR-25SEP
        name = "Box 1b";
        symbol = "BOX1b";
        maxSlippage = 0.01 ether; // 1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        box1b = new Box(
            address(usdc),
            owner,
            curator,
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            MAX_SHUTDOWN_WARMUP
        );
        // Creating the Box adapter between the vault and box1b
        adapter1b = BoxAdapterCached(address(boxAdapterCachedFactory.createBoxAdapter(address(vault), box1b)));

        // Allow box 2 to invest in PT-USR-25SEP
        vm.startPrank(curator);
        box1b.setGuardianInstant(guardian);
        box1b.addTokenInstant(stusd, stusdOracle);
        box1b.setIsAllocator(address(allocator), true);
        box1b.addFeederInstant(address(adapter1b));
        vault.addCollateralInstant(address(adapter1b), adapter1b.adapterData(), 1_000_000 * 10 ** 6, 1 ether); // 1,000,000 USDC absolute cap and 100% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter1b), 0.005 ether); // 0.5% penalty
        vm.stopPrank();

        // Creating Box 2 which will invest in PT-USR-25SEP
        name = "Box 2";
        symbol = "BOX2";
        maxSlippage = 0.01 ether; // 1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        box2 = new Box(
            address(usdc),
            owner,
            curator,
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            MAX_SHUTDOWN_WARMUP
        );
        // Creating the ERC4626 adapter between the vault and box2
        adapter2 = BoxAdapterCached(address(boxAdapterCachedFactory.createBoxAdapter(address(vault), box2)));

        // Allow box 2 to invest in PT-USR-25SEP
        vm.startPrank(curator);
        box2.setGuardianInstant(guardian);
        box2.addTokenInstant(ptusr25sep, ptusr25sepOracle);
        box2.setIsAllocator(address(allocator), true);
        box2.addFeederInstant(address(adapter2));
        vault.addCollateralInstant(address(adapter2), adapter2.adapterData(), 1_000_000 * 10 ** 6, 1 ether); // 1,000,000 USDC absolute cap and 100% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter2), 0.02 ether); // 2% penalty
        vm.stopPrank();
    }

    /////////////////////////////
    /// SCENARIOS
    /////////////////////////////

    /// @notice Test a simple flow
    function testDepositAllocationRedeem() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        uint256 USDC_500 = 500 * 10 ** 6;
        uint256 USDC_250 = 250 * 10 ** 6;

        // Cleaning the balance of USDC in case of
        usdc.transfer(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, usdc.balanceOf(address(this)));

        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_1000); // Transfer 1000 USDC to this contract
        assertEq(usdc.balanceOf(address(this)), USDC_1000);
        assertEq(vault.balanceOf(address(this)), 0);

        //////////////////////////////////////////////////////
        // Depositing and investing in bqqUSDC
        //////////////////////////////////////////////////////

        // Depositing 1000 USDC into the vault
        usdc.approve(address(vault), USDC_1000); // Approve the vault to spend USDC
        vault.deposit(USDC_1000, address(this)); // Deposit 1000 USDC into the vault
        assertEq(usdc.balanceOf(address(this)), 0);
        assertEq(vault.balanceOf(address(this)), 1000 ether);

        // Allocating 1000 USDC to the box1 as it is the liquidity adapter
        assertEq(
            bbqusdc.balanceOf(address(bbqusdcAdapter)),
            bbqusdc.previewDeposit(USDC_1000),
            "Allocation to bbqUSDC should result in gettiong the shares"
        );

        //////////////////////////////////////////////////////
        // Allocating 500 USDC to stUSD in Box1
        //////////////////////////////////////////////////////
        vm.startPrank(allocator);

        vault.deallocate(address(bbqusdcAdapter), "", USDC_500);
        vault.allocate(address(adapter1), "", USDC_500);

        assertEq(usdc.balanceOf(address(box1)), USDC_500, "500 USDC deposited in the Box1 contract but not yet invested");

        box1.allocate(stusd, USDC_250, swapper, "");
        assertEq(usdc.balanceOf(address(box1)), USDC_250, "Only 250 USDC left as half was allocated to stUSD");

        box1.allocate(stusd, USDC_250, swapper, "");
        assertEq(usdc.balanceOf(address(box1)), 0, "No USDC left as all was allocated to stUSD");
        assertEq(stusd.previewRedeem(stusd.balanceOf(address(box1))), 500 ether - 3, "Almost 500 USDA equivalent of stUSD (3 round down)");

        vm.stopPrank();

        //////////////////////////////////////////////////////
        // Allocating 500 USDC to Box2
        //////////////////////////////////////////////////////

        vm.startPrank(allocator);

        uint256 remainingUSDC = bbqusdc.previewRedeem(bbqusdc.balanceOf(address(bbqusdcAdapter)));

        vault.deallocate(address(bbqusdcAdapter), "", remainingUSDC);
        vault.allocate(address(adapter2), "", remainingUSDC);

        assertEq(usdc.balanceOf(address(box2)), remainingUSDC, "All USDC in bbqUSDC is now is Box2");

        vm.stopPrank();

        //////////////////////////////////////////////////////
        // Unwinding
        //////////////////////////////////////////////////////

        // No liquidity is available so we except a revert here
        vm.expectRevert();
        vault.withdraw(10 * 10 ** 6, address(this), address(this));

        // We exit stUSD but leave it in box1 for now
        vm.startPrank(allocator);
        box1.deallocate(stusd, stusd.balanceOf(address(box1)), swapper, "");
        vm.stopPrank();

        vm.expectRevert();
        vault.withdraw(10 * 10 ** 6, address(this), address(this));

        // We deallocate from box 1 to the vault liquidity sleeve
        uint256 box1Balance = usdc.balanceOf(address(box1));
        vm.prank(allocator);
        vault.deallocate(address(adapter1), "", box1Balance);
        vm.prank(allocator);
        vault.allocate(address(bbqusdcAdapter), "", box1Balance);
        vault.withdraw(USDC_500 - 3, address(this), address(this));
        assertEq(usdc.balanceOf(address(this)), USDC_500 - 3);

        // Testing the force deallocate
        // We are transfering the vault shares to an EOA
        uint256 shares = vault.balanceOf(address(this));
        vault.transfer(user, shares);

        // Impersonating the non permissioned user
        vm.startPrank(user);

        vm.expectRevert();
        vault.redeem(shares, address(this), address(this));

        vault.forceDeallocate(address(adapter2), "", usdc.balanceOf(address(box2)), address(user));
        assertLt(vault.balanceOf(address(user)), shares, "User lost some shares due to force deallocation");
        remainingUSDC = vault.previewRedeem(vault.balanceOf(address(user)));
        vault.redeem(vault.balanceOf(address(user)), address(user), address(user));
        assertEq(usdc.balanceOf(address(user)), remainingUSDC, "User should have received the USDC after redeem");

        console2.log("Vault total assets: ", vault.totalAssets());
        console2.log("Box 1 total assets: ", box1.totalAssets());
        console2.log("Box 2 total assets: ", box2.totalAssets());
        console2.log("bbqUSD adapter total assets: ", bbqusdc.convertToAssets(bbqusdc.balanceOf(address(bbqusdcAdapter))));
        console2.log("Liquidity total assets: ", usdc.balanceOf(address(vault)));
        console2.log("Vault total supply: ", vault.totalSupply());

        assertEq(vault.totalSupply(), 0, "Vault should have no shares left after redeeming all");

        vm.stopPrank();
    }

    /// @notice Test a simple flow
    function testCachedVsNonCached() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        uint256 USDC_250 = 250 * 10 ** 6;
        uint256 USDC_125 = 125 * 10 ** 6;

        // Cleaning the balance of USDC in case of
        usdc.transfer(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, usdc.balanceOf(address(this)));

        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(user), USDC_1000); // Transfer 1000 USDC to this contract
        assertEq(usdc.balanceOf(address(user)), USDC_1000);
        assertEq(vault.balanceOf(address(user)), 0);

        //////////////////////////////////////////////////////
        // Setting up the stage
        //////////////////////////////////////////////////////

        // Depositing 1000 USDC into the vault
        vm.startPrank(user);
        usdc.approve(address(vault), USDC_1000); // Approve the vault to spend USDC
        vault.deposit(USDC_1000, address(user)); // Deposit 1000 USDC into the vault
        vm.stopPrank();

        assertEq(bbqusdc.balanceOf(address(bbqusdcAdapter)), 977216327917259790879);

        // Compensate for rounding errors and keep things clean
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(vault), 1); // Transfer 1 to convert the conversion loss

        vm.startPrank(allocator);
        vault.deallocate(address(bbqusdcAdapter), "", bbqusdc.previewRedeem(977216327917259790879));

        vault.allocate(address(adapter1), "", USDC_250);
        box1.allocate(stusd, USDC_125, swapper, "");
        assertEq(stusd.previewRedeem(stusd.balanceOf(address(box1))), 125 ether - 1, "Almost 125 USDA equivalent of stUSD (1 round down)");
        assertEq(box1.totalAssets(), USDC_250 - 2, "Almost 250 USDC of total assets in Box1");

        vault.allocate(address(adapter1b), "", USDC_250);
        box1b.allocate(stusd, USDC_125, swapper, "");
        assertEq(stusd.previewRedeem(stusd.balanceOf(address(box1b))), 125 ether - 1, "Almost 125 USDA equivalent of stUSD (1 round down)");
        assertEq(box1b.totalAssets(), USDC_250 - 2, "Almost 250 USDC of total assets in Box1b");

        vm.stopPrank();

        // Test the real asset function on the adapters

        assertEq(adapter1.realAssets(), USDC_250 - 2, "Almost 250 USDC equivalent of stUSD");

        vm.prank(allocator);
        adapter1b.updateTotalAssets();
        assertEq(adapter1b.realAssets(), USDC_250 - 2, "Almost 250 USDC equivalent of stUSD");

        //////////////////////////////////////////////////////
        // Check real assets update with time
        //////////////////////////////////////////////////////

        vm.warp(block.timestamp + 1 days);

        assertGt(adapter1.realAssets(), USDC_250 - 2, "Adapter1 accrued value");

        assertEq(adapter1b.realAssets(), USDC_250 - 2, "Adapter1b doesn't accrue value");

        vm.prank(allocator);
        adapter1b.updateTotalAssets();
        assertGt(adapter1b.realAssets(), USDC_250 - 2, "Adapter1b accrued value");

        vm.startPrank(guardian);
        vm.stopPrank();

        //////////////////////////////////////////////////////
        // Test who can cache
        //////////////////////////////////////////////////////

        // Guardian (vault sentinel) should be able to update (we did allocator already)
        vm.prank(guardian);
        adapter1b.updateTotalAssets();

        // anyone else should fail
        vm.expectRevert(IBoxAdapter.NotAuthorized.selector);
        adapter1b.updateTotalAssets();

        // Except if we move 1 day forward
        vm.warp(adapter1b.totalAssetsTimestamp() + 1 days + 1);

        adapter1b.updateTotalAssets();

        // Should fail for a day
        vm.warp(adapter1b.totalAssetsTimestamp() + 1 days);

        vm.expectRevert(IBoxAdapter.NotAuthorized.selector);
        adapter1b.updateTotalAssets();

        // But work again after a day
        vm.warp(adapter1b.totalAssetsTimestamp() + 1 days + 1);

        adapter1b.updateTotalAssets();
    }

    /// @notice Test a Box with 2 feeders
    function testSharedBox() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        uint256 USDC_500 = 500 * 10 ** 6;

        // deactivate bbqusdc as the liquidity
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter1), "");

        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), 10 * USDC_1000); // Transfer 10000 USDC to this contract

        //////////////////////////////////////////////////////
        // Setting up the stage
        //////////////////////////////////////////////////////

        // Depositing 1000 USDC into the vault
        usdc.approve(address(vault), USDC_1000); // Approve the vault to spend USDC
        vault.deposit(USDC_1000, address(this)); // Deposit 1000 USDC into the vault

        vm.prank(curator);
        box1.addFeederInstant(address(this));
        usdc.approve(address(box1), USDC_1000); // Approve the vault to spend USDC
        box1.deposit(USDC_1000, address(this)); // Deposit 1000 USDC into the vault

        assertEq(vault.totalAssets(), USDC_1000, "Vault value is 1000 USDC");
        assertEq(box1.totalAssets(), 2 * USDC_1000, "Box value is 1000 USDC");

        // Test loss shared equally
        vm.prank(address(box1));
        usdc.transfer(address(1), USDC_1000);
        vault.resetFirstTotalAssets(); // transient issue for testing

        assertEq(box1.totalAssets(), USDC_1000, "Box value is now only 1000 USDC");
        assertEq(vault.totalAssets(), USDC_500, "Vault value is now down to 500 USDC");
    }

    /// @notice Test a Box with 2 feeders
    function testSharedBoxCached() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        uint256 USDC_500 = 500 * 10 ** 6;

        // deactivate bbqusdc as the liquidity
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter1b), "");

        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), 10 * USDC_1000); // Transfer 10000 USDC to this contract

        //////////////////////////////////////////////////////
        // Setting up the stage
        //////////////////////////////////////////////////////

        // Depositing 1000 USDC into the vault
        usdc.approve(address(vault), USDC_1000); // Approve the vault to spend USDC
        vault.deposit(USDC_1000, address(this)); // Deposit 1000 USDC into the vault

        vm.prank(curator);
        box1b.addFeederInstant(address(this));
        usdc.approve(address(box1b), USDC_1000); // Approve the vault to spend USDC
        box1b.deposit(USDC_1000, address(this)); // Deposit 1000 USDC into the vault

        assertEq(vault.totalAssets(), USDC_1000, "Vault value is 1000 USDC");
        assertEq(box1b.totalAssets(), 2 * USDC_1000, "Box value is 1000 USDC");

        // Test loss shared equally
        vm.prank(address(box1b));
        usdc.transfer(address(1), USDC_1000);
        vault.resetFirstTotalAssets(); // transient issue for testing

        assertEq(box1b.totalAssets(), USDC_1000, "Box value is now only 1000 USDC");

        assertEq(vault.totalAssets(), USDC_1000, "Vault value is still 1000 USDC as no update");
        assertEq(vault.allocation(adapter1b.ids()[0]), USDC_1000, "Allocation is again still 1000 USDC");

        vm.prank(allocator);
        vault.deallocate(address(adapter1b), "", 0);
        assertEq(vault.totalAssets(), USDC_500, "Vault value is still 500 USDC due to update");
        assertEq(vault.allocation(adapter1b.ids()[0]), USDC_500, "Allocation is now 500 USDC");

        usdc.transfer(address(box1b), USDC_1000);

        assertEq(box1b.totalAssets(), 2 * USDC_1000, "Box value is now back to 2000 USDC");

        assertEq(vault.totalAssets(), USDC_500, "Vault value is still 500 USDC as no update");
        assertEq(vault.allocation(adapter1b.ids()[0]), USDC_500, "Allocation is still 500 USDC");

        vm.prank(allocator);
        vault.allocate(address(adapter1b), "", 0); // We also test allocate

        // Vault V2 is limiting the value accrual per day
        vm.prank(allocator);
        vault.setMaxRate(200e16 / uint256(365 days)); // Make sure we can have up to 100% interest rate
        vm.warp(block.timestamp + 10000 days); // Go far enough

        vault.resetFirstTotalAssets(); // transient issue for testing
        assertEq(vault.totalAssets(), USDC_1000, "Vault value is back 1000 USDC due to update");
        assertEq(vault.allocation(adapter1b.ids()[0]), USDC_1000, "Allocation is back to 1000 USDC");
    }

    /// @notice Test guardian controlled shutdown
    function testGuardianControlledShutdown() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;

        // Cleaning the balance of USDC in case of
        usdc.transfer(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, usdc.balanceOf(address(this)));

        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(user), USDC_1000); // Transfer 1000 USDC to this contract
        assertEq(usdc.balanceOf(address(user)), USDC_1000);
        assertEq(vault.balanceOf(address(user)), 0);

        //////////////////////////////////////////////////////
        // Setting up the stage
        //////////////////////////////////////////////////////

        // Depositing 1000 USDC into the vault
        vm.startPrank(user);
        usdc.approve(address(vault), USDC_1000); // Approve the vault to spend USDC
        vault.deposit(USDC_1000, address(user)); // Deposit 1000 USDC into the vault
        vm.stopPrank();

        assertEq(bbqusdc.balanceOf(address(bbqusdcAdapter)), 977216327917259790879);

        // Compensate for rounding errors and keep things clean
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(vault), 1); // Transfer 1 to convert the conversion loss

        vm.startPrank(allocator);
        vault.deallocate(address(bbqusdcAdapter), "", bbqusdc.previewRedeem(977216327917259790879));
        assertEq(usdc.balanceOf(address(vault)), USDC_1000);
        vault.allocate(address(adapter2), "", USDC_1000);
        box2.allocate(ptusr25sep, USDC_1000, swapper, "");
        assertApproxEqRel(box2.totalAssets(), USDC_1000, 0.005 ether, "Around 1000 USDC of value in Box2");

        vm.stopPrank();

        // At this stage we have all in stUSD in box1 which is not the liquidity adapter

        //////////////////////////////////////////////////////
        // Now the guardian need to clean up the mess
        //////////////////////////////////////////////////////

        vm.startPrank(user);
        uint256 dealloc = ptusr25sep.balanceOf(address(box2));
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box2.deallocate(ptusr25sep, dealloc, swapper, "");
        vm.stopPrank();

        // start by calling a shutdown
        vm.prank(guardian);
        box2.shutdown();

        dealloc = ptusr25sep.balanceOf(address(box1));
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box2.deallocate(ptusr25sep, dealloc, swapper, "");

        // Move forward enough to have the maximum allowed slippage
        vm.warp(block.timestamp + box2.shutdownWarmup() + box2.shutdownSlippageDuration());

        vault.resetFirstTotalAssets();

        box2.deallocate(ptusr25sep, ptusr25sep.balanceOf(address(box2)), swapper, "");

        vm.startPrank(user);
        vault.forceDeallocate(address(adapter2), "", box2.convertToAssets(box2.balanceOf(address(adapter2))), user);

        vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();

        assertApproxEqRel(
            usdc.balanceOf(user),
            980 * 10 ** 6,
            0.005 ether,
            "User should have received the USDC after redeem (minus penalty and slippage)"
        );
    }

    /// @notice Test slippage events and reset in a Box
    function testSlippage() public {
        uint256 USDC_AMOUNT = 10_000 * 10 ** 6;

        // Disable bbqUSDC as liquidity
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(0), "");

        // We invest 50 USDC
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_AMOUNT); // Transfer 1000 USDC to this contract
        usdc.approve(address(vault), USDC_AMOUNT); // Approve the vault to spend USDC
        vault.deposit(USDC_AMOUNT, address(this)); // Deposit 1000 USDC into the vault

        //////////////////////////////////////////////////////
        // Invest half Box1
        //////////////////////////////////////////////////////
        vm.startPrank(allocator);

        assertEq(usdc.balanceOf(address(vault)), USDC_AMOUNT);
        vault.allocate(address(adapter2), "", USDC_AMOUNT);

        assertEq(box2.totalAssets(), 10000000000, "Total asset before allocate doesn't match");
        assertEq(box2.accumulatedSlippage(), 0, "Before the start, accumulated slippage should be 0");

        vm.expectEmit(true, true, true, true);
        emit EventsLib.SlippageAccumulated(430489300000000, 430489300000000);
        vm.expectEmit(true, true, true, true);
        emit EventsLib.Allocation(
            IERC20(ptusr25sep),
            USDC_AMOUNT,
            10102799289212086350341,
            10098450142215613367131,
            430489300239495,
            ISwapper(swapper),
            ""
        );
        box2.allocate(ptusr25sep, USDC_AMOUNT, swapper, "");

        assertEq(box2.totalAssets(), 9995695106, "Total asset after allocate doesn't match");
        assertEq(box2.accumulatedSlippage(), 430489300000000, "Accumulated slippage after allocate doesn't match");

        vm.expectEmit(true, true, true, true);
        emit EventsLib.SlippageAccumulated(463855584912436, 894344884912436);
        vm.expectEmit(true, true, true, true);
        emit EventsLib.Deallocation(
            IERC20(ptusr25sep),
            ptusr25sep.balanceOf(address(box2)),
            9995695106, // expected assets
            9991058547, // actual assets
            463855584912435,
            ISwapper(swapper),
            ""
        );
        box2.deallocate(ptusr25sep, ptusr25sep.balanceOf(address(box2)), swapper, "");

        assertEq(box2.totalAssets(), 9991058547, "Total asset after deallocate doesn't match");
        assertEq(box2.accumulatedSlippage(), 894344884912436, "Accumulated slippage after deallocate doesn't match");

        vm.warp(block.timestamp + 8 days);

        assertEq(box2.accumulatedSlippage(), 894344884912436, "Slippage doesn't change just by passage of time");

        vm.expectEmit(true, true, true, true);
        // August 22th, 2025 (8 days after August 14th)
        emit EventsLib.SlippageEpochReset(1755868569);
        vm.expectEmit(true, true, true, true);
        emit EventsLib.SlippageAccumulated(64150860190130, 64150860190130);
        box2.allocate(ptusr25sep, USDC_AMOUNT / 2, swapper, "");
        assertEq(box2.accumulatedSlippage(), 64150860190130, "Slippage reset");

        vm.stopPrank();
    }

    /// @notice Test impact of a loss in a Box
    function testBoxLoss() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        uint256 USDC_500 = 500 * 10 ** 6;

        //////////////////////////////////////////////////////
        // Setup 500 USDC liquid and 500 USDC in Box1
        //////////////////////////////////////////////////////

        // Disable bbqUSDC as liquidity
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(0), "");

        // We invest 50 USDC
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_1000); // Transfer 1000 USDC to this contract
        usdc.approve(address(vault), USDC_1000); // Approve the vault to spend USDC
        vault.deposit(USDC_1000, address(this)); // Deposit 1000 USDC into the vault

        vm.prank(allocator);
        vault.allocate(address(adapter1), "", USDC_500);

        assertEq(usdc.balanceOf(address(box1)), USDC_500, "500 USDC deposited in the Box1 contract but not yet invested");
        assertEq(usdc.balanceOf(address(vault)), USDC_500, "500 USDC liquid in the vault");
        assertEq(vault.totalAssets(), USDC_1000, "Vault value is 1000 USDC");

        //////////////////////////////////////////////////////
        // Simulating a loss in Box1
        //////////////////////////////////////////////////////

        vm.prank(address(box1));
        usdc.transfer(address(this), USDC_500);
        assertEq(usdc.balanceOf(address(box1)), 0, "No more USDC in the Box1 contract");
        assertEq(box1.totalAssets(), 0, "Total assets at Box1 level is 0");

        // Just to allow totalAssets to work
        vault.resetFirstTotalAssets();
        assertEq(vault.totalAssets(), USDC_500, "Vault value is 500 USDC an");

        usdc.transfer(address(box1), USDC_500);

        assertEq(usdc.balanceOf(address(box1)), USDC_500, "500 USDC back in the Box1 contract");
        assertEq(box1.totalAssets(), USDC_500, "Total assets at Box1 level is again 0");

        // Just to allow totalAssets to work
        vault.resetFirstTotalAssets();
        assertEq(vault.totalAssets(), USDC_1000, "Vault value is back to 1000 USDC an");
    }

    function testBoxLeverageMorpho() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        FundingMorpho fundingModule2 = new FundingMorpho(address(box2), address(morpho), 99e16);
        MarketParams memory market = MarketParams(address(usdc), address(ptusr25sep), address(ptusr25sepOracle), irm, 915000000000000000);
        bytes memory facilityData2 = fundingModule2.encodeFacilityData(market);

        vm.startPrank(curator);

        // And this contract to be a feeder
        box2.addFeederInstant(address(this));

        // Add the funding module and facility
        box2.addFundingInstant(fundingModule2);
        box2.addFundingCollateralInstant(fundingModule2, ptusr25sep);
        box2.addFundingDebtInstant(fundingModule2, usdc);
        box2.addFundingFacilityInstant(fundingModule2, facilityData2);
        vm.stopPrank();

        assertEq(box2.fundingsLength(), 1, "There is one source of funding");
        IFunding funding = box2.fundings(0);
        assertEq(address(funding.debtTokens(0)), address(usdc), "Loan token is USDC");
        assertEq(address(funding.collateralTokens(0)), address(ptusr25sep), "Collateral token is ptusr25sep");

        // Get some USDC
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_1000); // Transfer 1000 USDC to this contract

        usdc.approve(address(box2), USDC_1000);
        box2.deposit(USDC_1000, address(this)); // Deposit 1000 USDC

        vm.startPrank(allocator);

        box2.allocate(ptusr25sep, USDC_1000, swapper, "");
        uint256 ptBalance = ptusr25sep.balanceOf(address(box2));

        assertEq(usdc.balanceOf(address(box2)), 0, "No more USDC in the Box");
        assertEq(ptBalance, 1010280676747326095928, "ptusr25sep in the Box");

        box2.pledge(fundingModule2, facilityData2, ptusr25sep, ptBalance);

        assertEq(ptusr25sep.balanceOf(address(box2)), 0, "No more ptusr25sep in the Box");
        assertEq(fundingModule2.collateralBalance(facilityData2, ptusr25sep), ptBalance, "Collateral is correct");

        box2.borrow(fundingModule2, facilityData2, usdc, 500 * 10 ** 6);

        assertEq(usdc.balanceOf(address(box2)), 500 * 10 ** 6, "500 USDC in the Box");

        // Get some USDC to cover rounding
        vm.stopPrank();
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(box2), 1);
        vm.startPrank(allocator);

        box2.repay(fundingModule2, facilityData2, usdc, type(uint256).max);

        box2.depledge(fundingModule2, facilityData2, ptusr25sep, ptBalance);
        assertEq(ptusr25sep.balanceOf(address(box2)), 1010280676747326095928, "ptusr25sep are back in the Box");

        vm.stopPrank();
    }

    function testBoxWind() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        FundingMorpho fundingModule2 = new FundingMorpho(address(box2), address(morpho), 99e16);
        MarketParams memory market = MarketParams(address(usdc), address(ptusr25sep), address(ptusr25sepOracle), irm, 915000000000000000);
        bytes memory facilityData2 = fundingModule2.encodeFacilityData(market);

        vm.startPrank(curator);

        // And this contract to be a feeder
        box2.addFeederInstant(address(this));
        box2.setIsAllocator(address(box2), true);

        // Add the funding module and facility
        box2.addFundingInstant(fundingModule2);
        box2.addFundingCollateralInstant(fundingModule2, ptusr25sep);
        box2.addFundingDebtInstant(fundingModule2, usdc);
        box2.addFundingFacilityInstant(fundingModule2, facilityData2);
        vm.stopPrank();

        assertEq(box2.fundingsLength(), 1, "There is one source of funding");
        IFunding funding = box2.fundings(0);
        assertEq(address(funding.debtTokens(0)), address(usdc), "Loan token is USDC");
        assertEq(address(funding.collateralTokens(0)), address(ptusr25sep), "Collateral token is ptusr25sep");

        // Get some USDC
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_1000); // Transfer 1000 USDC to this contract

        usdc.approve(address(box2), USDC_1000);
        box2.deposit(USDC_1000, address(this)); // Deposit 1000 USDC

        vm.startPrank(allocator);

        box2.allocate(ptusr25sep, USDC_1000, swapper, "");
        uint256 ptBalance = ptusr25sep.balanceOf(address(box2));

        assertEq(usdc.balanceOf(address(box2)), 0, "No more USDC in the Box");
        assertEq(ptBalance, 1010280676747326095928, "ptusr25sep in the Box");

        box2.pledge(fundingModule2, facilityData2, ptusr25sep, ptBalance);

        assertEq(ptusr25sep.balanceOf(address(box2)), 0, "No more ptusr25sep in the Box");
        assertEq(fundingModule2.collateralBalance(facilityData2, ptusr25sep), ptBalance, "Collateral is correct");

        FlashLoanMorpho flashloanProvider = new FlashLoanMorpho(address(morpho));
        vm.stopPrank();
        vm.prank(curator);
        box2.setIsAllocator(address(flashloanProvider), true);
        vm.startPrank(allocator);

        flashloanProvider.leverage(box2, fundingModule2, facilityData2, swapper, "", ptusr25sep, usdc, 500 * 10 ** 6);

        assertEq(fundingModule2.debtBalance(facilityData2, usdc), 500 * 10 ** 6 + 1, "Debt is correct");
        assertEq(
            fundingModule2.collateralBalance(facilityData2, ptusr25sep),
            1515398374089157807752,
            "Collateral after leverage is correct"
        );

        vm.stopPrank();
    }
}
