// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {StreamVault} from "../../src/StreamVault.sol";
import {StableWrapper} from "../../src/StableWrapper.sol";
import {Vault} from "../../src/lib/Vault.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract Base is TestHelperOz5 {
    // contract
    StreamVault streamVault;
    StableWrapper stableWrapper;

    // assets
    MockERC20 usdc;

    // depositors
    address depositor1;
    address depositor2;
    address depositor3;
    address depositor4;
    address depositor5;
    address depositor6;
    address depositor7;
    address depositor8;
    address depositor9;
    address depositor10;
    address[] depositors;

    // admin
    address keeper;
    address keeper2;
    address owner;

    // layerzero
    uint32 private aEid = 1;
    uint32 private bEid = 2;
    address lzDelegate;

    // helper
    uint8 decimals = 6;
    uint256 startingBal = 10000 * (10 ** 6);
    uint104 cap = 10 ** 24;
    uint56 minSupply = 10 ** 3;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);
        depositor1 = vm.addr(1);
        depositor2 = vm.addr(2);
        depositor3 = vm.addr(3);
        depositor4 = vm.addr(4);
        depositor5 = vm.addr(5);
        depositor6 = vm.addr(6);
        depositor7 = vm.addr(7);
        depositor8 = vm.addr(8);
        depositor9 = vm.addr(9);
        depositor10 = vm.addr(10);

        depositors = [
            depositor1,
            depositor2,
            depositor3,
            depositor4,
            depositor5,
            depositor6,
            depositor7,
            depositor8,
            depositor9,
            depositor10
        ];

        keeper = vm.addr(11);
        keeper2 = vm.addr(12);
        owner = vm.addr(13);

        // lzEndpoint = vm.addr(14);
        lzDelegate = vm.addr(15);

        usdc = new MockERC20("USD Coin", "USDC");

        vm.startPrank(owner);
        stableWrapper = new StableWrapper(
            address(usdc),
            "Wrapped USD Coin",
            "wUSDC",
            decimals,
            keeper,
            address(endpoints[aEid]),
            lzDelegate
        );

        Vault.VaultParams memory vaultParams = Vault.VaultParams({
            decimals: decimals,
            minimumSupply: minSupply,
            cap: cap
        });

        streamVault = new StreamVault(
            "Stream Yield Bearing USDC",
            "syUSDC",
            address(stableWrapper),
            address(endpoints[aEid]),
            lzDelegate,
            vaultParams
        );

        stableWrapper.setKeeper(address(streamVault));
        keeper = address(streamVault);
        vm.stopPrank();

        // fund deposits with 10_000 USDC and 100 ETH each and approve vault
        for (uint256 i = 0; i < depositors.length; i++) {
            vm.startPrank(depositors[i]);
            usdc.mint(depositors[i], startingBal);
            usdc.approve(address(stableWrapper), startingBal);
            vm.deal(depositors[i], 10 * (10 ** 18));
            vm.stopPrank();
        }
    }

    function verifyVaultState(Vault.VaultState memory state) public {
        (uint16 round, uint128 totalPending) = streamVault.vaultState();
        assertEq(round, state.round);
        assertEq(totalPending, state.totalPending);
    }

    function assertBaseState() public {
        assertEq(streamVault.name(), "Stream Yield Bearing USDC");
        assertEq(streamVault.symbol(), "syUSDC");
        assertEq(streamVault.decimals(), 6);
        assertEq(streamVault.totalSupply(), 0);
        assertEq(address(streamVault.endpoint()), address(endpoints[1]));
        assertEq(streamVault.owner(), owner);
        assertEq(streamVault.stableWrapper(), address(stableWrapper));
        verifyVaultState(Vault.VaultState(uint16(1), uint128(0)));
        assertEq(stableWrapper.balanceOf(address(streamVault)), 0);
        assertEq(streamVault.omniTotalSupply(), 0);
    }

    function assertVaultState(uint16 round, uint128 totalPending) public {
        (uint16 _round, uint128 _totalPending) = streamVault.vaultState();
        assertEq(_round, round);
        assertEq(_totalPending, totalPending);
    }

    function assertStakeReceipt(
        address depositor,
        uint16 round,
        uint104 amount,
        uint128 unredeemedShares
    ) public {
        (
            uint16 _round,
            uint104 _amount,
            uint128 _unredeemedShares
        ) = streamVault.stakeReceipts(depositor);
        assertEq(_round, round);
        assertEq(_amount, amount);
        assertEq(_unredeemedShares, unredeemedShares);
    }

    function assertAccountVaultBalance(
        address _depositor,
        uint256 _balance
    ) public {
        uint256 balance = streamVault.accountVaultBalance(_depositor);
        assertEq(balance, _balance);
    }

    function assertShares(address _depositor, uint256 _shares) public {
        uint256 shares = streamVault.shares(_depositor);
        assertEq(shares, _shares);
    }

    function assertSharesHeldByVault(
        address _depositor,
        uint256 _shares
    ) public {
        uint256 shares = streamVault.shareBalancesHeldByVault(_depositor);
        assertEq(shares, _shares);
    }

    function assertSharesHeldByAccount(
        address _depositor,
        uint256 _shares
    ) public {
        uint256 shares = streamVault.shareBalancesHeldByAccount(_depositor);
        assertEq(shares, _shares);
    }

    function stakeAssets(
        address _depositor,
        address _creditor,
        uint104 _amount
    ) public {
        vm.prank(_depositor);
        streamVault.depositAndStake(_amount, _creditor);
    }

    function rollRound(uint256 _yield, bool _isPositive) public {
        vm.prank(owner);
        streamVault.rollToNextRound(_yield, _isPositive);
    }

    function stakeAndRollRound(
        address _depositor,
        address _creditor,
        uint104 _amount
    ) public {
        stakeAssets(_depositor, _creditor, _amount);
        rollRound(0, true);
    }

    function assertOneRollBaseState(uint104 _amount, uint16 _round) public {
        assertEq(streamVault.totalSupply(), uint256(_amount));
        assertEq(streamVault.balanceOf(address(streamVault)), uint256(_amount));
        assertEq(streamVault.omniTotalSupply(), uint256(_amount));
        verifyVaultState(Vault.VaultState(_round, uint128(0)));
    }

    function assertPricePerShare(
        uint256 _round,
        uint256 _pricePerShare
    ) public {
        uint256 pricePerShare = streamVault.roundPricePerShare(_round);
        assertEq(pricePerShare, _pricePerShare);
    }
}
