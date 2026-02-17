// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { AccessControl } from "../../contracts/access/AccessControl.sol";

import { ProxyUtils } from "../../contracts/deploy/utils/ProxyUtils.sol";
import { FeeAuction } from "../../contracts/feeAuction/FeeAuction.sol";
import { Vault } from "../../contracts/vault/Vault.sol";

import { MockAccessControl } from "../mocks/MockAccessControl.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { MockERC4626 } from "../mocks/MockERC4626.sol";
import { MockOracle } from "../mocks/MockOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";

import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract VaultInvariantsTest is Test, ProxyUtils {
    TestVaultHandler public handler;
    TestVault public vault;
    FeeAuction public feeAuction;
    address[] public assets;

    MockOracle public mockOracle;
    MockAccessControl public accessControl;

    address[] public fractionalReserveVaults;

    // Track token holders for testing
    address[] private tokenHolders;
    mapping(address => bool) private isHolder;

    // Mock tokens
    MockERC20[] private mockTokens;

    function setUp() public {
        // Setup mock assets
        mockTokens = new MockERC20[](3);
        assets = new address[](3);

        // Create mock tokens with different decimals
        mockTokens[0] = new MockERC20("Mock Token 1", "MT1", 18);
        mockTokens[1] = new MockERC20("Mock Token 2", "MT2", 6);
        mockTokens[2] = new MockERC20("Mock Token 3", "MT3", 8);

        for (uint256 i = 0; i < 3; i++) {
            assets[i] = address(mockTokens[i]);
        }

        // Deploy and setup mock oracle
        mockOracle = new MockOracle();
        for (uint256 i = 0; i < assets.length; i++) {
            // Set initial price of 1:1 for each asset
            mockOracle.setPrice(assets[i], 10 ** IERC20Metadata(assets[i]).decimals());
        }

        // Deploy and initialize mock access control
        accessControl = new MockAccessControl();

        // Deploy and initialize fee auction with proxy
        FeeAuction feeAuctionImpl = new FeeAuction();
        address proxy = _proxy(address(feeAuctionImpl));
        feeAuction = FeeAuction(proxy);
        feeAuction.initialize(address(accessControl), address(mockTokens[0]), address(this), 1 days, 1e18);

        // Deploy and initialize vault
        vault = new TestVault();
        vault.initialize(
            "Test Vault", "tVAULT", address(accessControl), address(feeAuction), address(mockOracle), assets
        );
        mockOracle.setPrice(address(vault), 1e18);

        // Setup initial test accounts
        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("User", vm.toString(i))));
            tokenHolders.push(user);
            isHolder[user] = true;
        }

        // Create fractional reserve vaults, one for each asset
        fractionalReserveVaults = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            address asset = assets[i];
            address frVault = address(new MockERC4626(asset, 1e18, "Fractional Reserve Vault", "FRV"));
            fractionalReserveVaults[i] = frVault;
            vault.setFractionalReserveVault(asset, frVault);
        }

        // Create and target handler
        handler = new TestVaultHandler(vault, mockOracle, assets, tokenHolders);
        targetContract(address(handler));

        // we need to set an appropriate block.number and block.timestamp for the tests
        // otherwise they will default to 0 and the tests will fail trying to subtract staleness from 0
        vm.roll(block.number + 1_000_000);
        vm.warp(block.timestamp + 1_000_000);
    }

    /// @dev Test that total assets >= total borrowed
    function invariant_totalAssetsExceedBorrowed() public view {
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 totalAssets = vault.totalSupplies(asset);
            uint256 totalBorrowed = vault.totalBorrows(asset);
            assertGe(totalAssets, totalBorrowed, "Total assets must exceed borrowed");
        }
    }

    /// @dev Test that minting increases asset balance correctly
    function invariant_mintingIncreaseBalance() public {
        address[] memory unpausedAssets = handler.getUnpausedAssets();

        for (uint256 i = 0; i < unpausedAssets.length; i++) {
            address asset = unpausedAssets[i];

            uint256 amount = 1000 * (10 ** IERC20Metadata(asset).decimals());

            uint256 balanceBefore = IERC20(asset).balanceOf(address(vault));
            uint256 supplyBefore = vault.totalSupplies(asset);

            address minter = makeAddr("Minter");
            MockERC20(asset).mint(minter, amount);

            vm.startPrank(minter);
            IERC20(asset).approve(address(vault), amount);
            vault.mint(asset, amount, 0, minter, block.timestamp);
            vm.stopPrank();

            uint256 balanceAfter = IERC20(asset).balanceOf(address(vault));
            uint256 supplyAfter = vault.totalSupplies(asset);

            assertEq(balanceAfter - balanceBefore, amount, "Asset balance should increase by exact amount");
            assertTrue(supplyAfter > supplyBefore, "Total supply should increase");
        }
    }
}

contract TestVault is Vault {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _accessControl,
        address _feeAuction,
        address _oracle,
        address[] calldata _assets
    ) external initializer {
        __Vault_init(_name, _symbol, _accessControl, _feeAuction, _oracle, _assets);
    }
}
/**
 * @notice This is a helper contract to test the vault invariants in a meaningful way
 */

contract TestVaultHandler is StdUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Vault public vault;
    MockOracle public mockOracle;

    address[] public assets;
    address[] public actors;
    uint256 private constant MAX_ASSETS = 10;

    address[] private addyArr; // working var

    // Ghost variables for tracking state
    mapping(address => uint256) public sumDeposits;
    mapping(address => mapping(address => uint256)) public sumBorrows;
    uint256 public sumBalanceOf;

    // Actor management
    address internal currentActor;
    address internal currentAsset;
    address internal currentSpender;

    // Ghost variables for tracking state
    address[] public tokenHolders;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useAsset(uint256 assetSeed) {
        currentAsset = assets[bound(assetSeed, 0, assets.length - 1)];
        _;
    }

    modifier useAssetInVault(uint256 assetSeed) {
        address[] memory vaultAssets = vault.assets();
        if (vaultAssets.length == 0) return;
        currentAsset = vaultAssets[bound(assetSeed, 0, vaultAssets.length - 1)];
        _;
    }

    modifier useUnpausedAssetInVault(uint256 assetSeed) {
        address[] memory _unpausedAssets = getUnpausedAssets();
        if (_unpausedAssets.length == 0) return;

        currentAsset = _unpausedAssets[bound(assetSeed, 0, _unpausedAssets.length - 1)];
        _;
    }

    function getUnpausedAssets() public returns (address[] memory) {
        address[] memory vaultAssets = vault.assets();

        delete addyArr;

        for (uint256 i = 0; i < vaultAssets.length; i++) {
            address asset = vaultAssets[i];
            if (!vault.paused(asset)) {
                addyArr.push(asset);
            }
        }

        return addyArr;
    }

    modifier useSpender(uint256 spenderSeed) {
        currentSpender = actors[bound(spenderSeed, 0, actors.length - 1)];
        if (currentSpender == currentActor) {
            currentSpender = actors[(bound(spenderSeed, 0, actors.length - 1) + 1) % actors.length];
        }
        _;
    }

    function isAssetInVault(address asset) public view returns (bool) {
        address[] memory vaultAssets = vault.assets();
        for (uint256 i = 0; i < vaultAssets.length; i++) {
            if (vaultAssets[i] == asset) {
                return true;
            }
        }
        return false;
    }

    constructor(Vault _vault, MockOracle _mockOracle, address[] memory _assets, address[] memory _actors) {
        vault = _vault;
        mockOracle = _mockOracle;
        assets = _assets;
        actors = _actors;
    }

    function addAsset(uint256 assetSeed) external useAsset(assetSeed) {
        if (assets.length >= MAX_ASSETS) return;
        if (isAssetInVault(currentAsset)) return;

        vault.addAsset(currentAsset);
    }

    function approve(uint256 actorSeed, uint256 spenderSeed, uint256 amount)
        external
        useActor(actorSeed)
        useSpender(spenderSeed)
    {
        amount = bound(amount, 0, type(uint96).max); // Reasonable bound for approval
        vault.approve(currentSpender, amount);
    }

    function borrow(uint256 actorSeed, uint256 assetSeed, uint256 amount)
        external
        useActor(actorSeed)
        useUnpausedAssetInVault(assetSeed)
    {
        uint256 maxBorrow = vault.availableBalance(currentAsset);
        amount = bound(amount, 0, Math.min(maxBorrow, type(uint96).max)); // Reasonable bound for borrow

        uint256 beforeBalance = IERC20(currentAsset).balanceOf(currentActor);
        vault.borrow(currentAsset, amount, currentActor);
        uint256 afterBalance = IERC20(currentAsset).balanceOf(currentActor);

        uint256 borrowed = afterBalance - beforeBalance;
        sumBorrows[currentActor][currentAsset] += borrowed;
    }

    function burn(uint256 actorSeed, uint256 assetSeed, uint256 amount)
        external
        useActor(actorSeed)
        useUnpausedAssetInVault(assetSeed)
    {
        uint256 maxBurn = vault.balanceOf(currentActor);
        if (maxBurn == 0) return;

        amount = bound(amount, 1, Math.min(maxBurn, type(uint96).max)); // Reasonable bound for burn

        uint256 beforeBalance = vault.balanceOf(currentActor);
        vault.burn(currentAsset, amount, 0, currentActor, block.timestamp);
        uint256 afterBalance = vault.balanceOf(currentActor);

        sumBalanceOf -= (beforeBalance - afterBalance);
    }

    function divestAll(uint256 assetSeed) external useUnpausedAssetInVault(assetSeed) {
        vault.divestAll(currentAsset);
    }

    function investAll(uint256 assetSeed) external useUnpausedAssetInVault(assetSeed) {
        vault.investAll(currentAsset);
    }

    function mint(uint256 actorSeed, uint256 assetSeed, uint256 amount)
        external
        useActor(actorSeed)
        useUnpausedAssetInVault(assetSeed)
    {
        uint256 maxMint = vault.availableBalance(currentAsset);
        if (maxMint == 0) return;
        amount = bound(amount, 1, Math.min(maxMint, type(uint96).max)); // Reasonable bound for mint

        // Mint tokens to the actor first
        MockERC20(currentAsset).mint(currentActor, amount);

        uint256 beforeBalance = vault.balanceOf(currentActor);
        IERC20(currentAsset).approve(address(vault), amount);
        vault.mint(currentAsset, amount, 0, currentActor, block.timestamp);
        uint256 afterBalance = vault.balanceOf(currentActor);

        sumDeposits[currentActor] += amount;
        sumBalanceOf += (afterBalance - beforeBalance);
    }

    function redeem(uint256 actorSeed, uint256 assetSeed, uint256 amount)
        external
        useActor(actorSeed)
        useUnpausedAssetInVault(assetSeed)
    {
        uint256 maxRedeem = vault.balanceOf(currentActor);
        if (maxRedeem == 0) return;

        amount = bound(amount, 1, Math.min(maxRedeem, type(uint96).max)); // Reasonable bound for redeem

        uint256[] memory amountsOut = new uint256[](1);
        amountsOut[0] = 0;

        vault.redeem(amount, amountsOut, currentActor, block.timestamp);
    }

    function removeAsset(uint256 assetSeed) external useUnpausedAssetInVault(assetSeed) {
        vault.removeAsset(currentAsset);
    }

    function repay(uint256 actorSeed, uint256 assetSeed, uint256 amount)
        external
        useActor(actorSeed)
        useUnpausedAssetInVault(assetSeed)
    {
        amount = bound(amount, 0, sumBorrows[currentActor][currentAsset]);

        // Mint tokens to the actor first
        MockERC20(currentAsset).mint(currentActor, amount);

        IERC20(currentAsset).approve(address(vault), amount);
        vault.repay(currentAsset, amount);

        sumBorrows[currentActor][currentAsset] -= amount;
    }

    function rescueERC20(IERC20 asset, uint256 receiverSeed) external useActor(receiverSeed) {
        if (address(asset).code.length == 0) {
            return;
        }

        try IERC20(asset).balanceOf(address(vault)) returns (uint256 amount) {
            if (amount > 0) {
                vault.rescueERC20(address(asset), currentActor);
            }
        } catch {
            // Do nothing if the asset is not in the vault
        }
    }

    function pause(uint256 assetSeed) external useUnpausedAssetInVault(assetSeed) {
        vault.pause(currentAsset);
    }

    function unpause(uint256 assetSeed) external useAssetInVault(assetSeed) {
        vault.unpause(currentAsset);
    }

    function setAssetOraclePrice(uint256 assetSeed, uint256 price) external useAsset(assetSeed) {
        uint256 decimals = IERC20Metadata(currentAsset).decimals();
        uint256 boundPrice = bound(price, 10 ** (decimals - 1), 10 ** decimals);
        mockOracle.setPrice(currentAsset, boundPrice);
    }
}
