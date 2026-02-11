// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IERC20Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

import "./helpers/IntegrationTest.sol";

contract ERC4626Test is IntegrationTest {
    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();
    }

    function testDecimals(uint8 decimals) public {
        vm.mockCall(address(loanToken), abi.encodeWithSignature("decimals()"), abi.encode(decimals));

        vault = eeFactory.createEulerEarn(
            OWNER, TIMELOCK, address(loanToken), "EulerEarn Vault", "EEV", bytes32(uint256(2))
        );

        assertEq(vault.decimals(), decimals, "decimals");
    }

    function testMint(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        uint256 shares = vault.convertToShares(assets);

        loanToken.setBalance(SUPPLIER, assets);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() + assets);
        vm.prank(SUPPLIER);
        uint256 deposited = vault.mint(shares, ONBEHALF);

        assertGt(deposited, 0, "deposited");
        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), assets, "expectedSupplyAssets(vault)");
    }

    function testDeposit(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() + assets);
        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), assets, "expectedSupplyAssets(vault)");
    }

    function testRedeem(uint256 deposited, uint256 redeemed) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        redeemed = bound(redeemed, 0, shares);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() - vault.convertToAssets(redeemed));

        vm.prank(ONBEHALF);
        vault.redeem(redeemed, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
    }

    function testWithdraw(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, 0, deposited);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() - withdrawn);
        vm.prank(ONBEHALF);
        uint256 redeemed = vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
    }

    function testWithdrawIdle(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, 0, deposited);

        _setCap(allMarkets[0], 0);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() - withdrawn);
        vm.prank(ONBEHALF);
        uint256 redeemed = vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(vault)), 0, "balanceOf(vault)");
        assertEq(vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
        assertEq(_idle(), deposited - withdrawn, "idle");
    }

    function testRedeemTooMuch(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited * 2);

        vm.startPrank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, SUPPLIER);
        vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        vm.prank(SUPPLIER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SUPPLIER, shares, shares + 1)
        );
        vault.redeem(shares + 1, RECEIVER, SUPPLIER);
    }

    function testWithdrawAll(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        uint256 minted = vault.deposit(assets, ONBEHALF);

        assertEq(vault.maxWithdraw(ONBEHALF), assets, "maxWithdraw(ONBEHALF)");

        vm.prank(ONBEHALF);
        uint256 shares = vault.withdraw(assets, RECEIVER, ONBEHALF);

        assertEq(shares, minted, "shares");
        assertEq(vault.balanceOf(ONBEHALF), 0, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), assets, "loanToken.balanceOf(RECEIVER)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), 0, "expectedSupplyAssets(vault)");
    }

    function testRedeemAll(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 minted = vault.deposit(deposited, ONBEHALF);

        assertEq(vault.maxRedeem(ONBEHALF), minted, "maxRedeem(ONBEHALF)");

        vm.prank(ONBEHALF);
        uint256 assets = vault.redeem(minted, RECEIVER, ONBEHALF);

        assertEq(assets, deposited, "assets");
        assertEq(vault.balanceOf(ONBEHALF), 0, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), deposited, "loanToken.balanceOf(RECEIVER)");
        assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), 0, "expectedSupplyAssets(vault)");
    }

    function testWithdrawAllWithUntrackedBalance(uint256 assets, uint256 marketIndex, uint256 untrackedAssets) public {
        uint256 cap = MAX_TEST_ASSETS / 2;
        _setCap(allMarkets[0], cap);

        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        marketIndex = bound(marketIndex, 0, vault.supplyQueueLength() - 1);
        untrackedAssets = bound(untrackedAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        IERC4626 market = IERC4626(vault.supplyQueue(marketIndex));

        loanToken.setBalance(SUPPLIER, assets + untrackedAssets);

        vm.startPrank(SUPPLIER);
        uint256 minted = vault.deposit(assets, ONBEHALF);

        // deposit directly to strategy for vault - untracked shares balance
        loanToken.approve(address(market), untrackedAssets);
        uint256 maxBefore = market.maxWithdraw(address(vault));
        uint256 mintedUntracked = market.deposit(untrackedAssets, address(vault));
        uint256 maxAfter = market.maxWithdraw(address(vault));
        assertEq(maxAfter - maxBefore, untrackedAssets, "maxWithdraw(vault)");

        // untracked shares are not included in maxWithdraw
        assertEq(vault.maxWithdraw(ONBEHALF), assets, "maxWithdraw(ONBEHALF)");

        vm.startPrank(ONBEHALF);
        uint256 shares = vault.withdraw(assets, RECEIVER, ONBEHALF);

        assertEq(shares, minted, "shares");
        assertEq(vault.balanceOf(ONBEHALF), 0, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), assets, "loanToken.balanceOf(RECEIVER)");

        // untracked shares remain in the vault
        assertEq(market.balanceOf(address(vault)), mintedUntracked);
        if (address(market) != address(allMarkets[0])) {
            assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), 0, "expectedSupplyAssets(vault)");
        }
    }

    function testRedeemAllWithUntrackedBalance(uint256 deposited, uint256 marketIndex, uint256 untrackedAssets)
        public
    {
        uint256 cap = MAX_TEST_ASSETS / 2;
        _setCap(allMarkets[0], cap);

        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        marketIndex = bound(marketIndex, 0, vault.supplyQueueLength() - 1);
        untrackedAssets = bound(untrackedAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        IERC4626 market = IERC4626(vault.supplyQueue(marketIndex));

        loanToken.setBalance(SUPPLIER, deposited + untrackedAssets);

        vm.startPrank(SUPPLIER);
        uint256 minted = vault.deposit(deposited, ONBEHALF);

        // deposit directly to strategy for vault - untracked shares balance
        loanToken.approve(address(market), untrackedAssets);
        uint256 maxBefore = market.maxWithdraw(address(vault));
        uint256 mintedUntracked = market.deposit(untrackedAssets, address(vault));
        uint256 maxAfter = market.maxWithdraw(address(vault));
        assertEq(maxAfter - maxBefore, untrackedAssets, "maxWithdraw(vault)");

        // untracked shares are not included in maxRedeem
        assertEq(vault.maxRedeem(ONBEHALF), minted, "maxRedeem(ONBEHALF)");

        vm.startPrank(ONBEHALF);
        uint256 assets = vault.redeem(minted, RECEIVER, ONBEHALF);

        assertEq(assets, deposited, "assets");
        assertEq(vault.balanceOf(ONBEHALF), 0, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), deposited, "loanToken.balanceOf(RECEIVER)");

        // untracked shares remain in the vault
        assertEq(market.balanceOf(address(vault)), mintedUntracked);
        if (address(market) != address(allMarkets[0])) {
            assertEq(_expectedSupplyAssets(allMarkets[0], address(vault)), 0, "expectedSupplyAssets(vault)");
        }
    }

    function testRedeemNotDeposited(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        vm.prank(SUPPLIER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SUPPLIER, 0, shares));
        vault.redeem(shares, SUPPLIER, SUPPLIER);
    }

    function testRedeemNotApproved(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        vm.prank(RECEIVER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, RECEIVER, 0, shares));
        vault.redeem(shares, RECEIVER, ONBEHALF);
    }

    function testWithdrawNotApproved(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 shares = vault.previewWithdraw(assets);
        vm.prank(RECEIVER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, RECEIVER, 0, shares));
        vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testTransferFrom(uint256 deposited, uint256 toTransfer) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        toTransfer = bound(toTransfer, 0, shares);

        vm.prank(ONBEHALF);
        vault.approve(SUPPLIER, toTransfer);

        vm.prank(SUPPLIER);
        vault.transferFrom(ONBEHALF, RECEIVER, toTransfer);

        assertEq(vault.balanceOf(ONBEHALF), shares - toTransfer, "balanceOf(ONBEHALF)");
        assertEq(vault.balanceOf(RECEIVER), toTransfer, "balanceOf(RECEIVER)");
        assertEq(vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER)");
    }

    function testTransferFromNotApproved(uint256 deposited, uint256 amount) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        amount = bound(amount, 0, shares);

        vm.prank(SUPPLIER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SUPPLIER, 0, shares));
        vault.transferFrom(ONBEHALF, RECEIVER, shares);
    }

    function testWithdrawMoreThanBalanceButLessThanTotalAssets(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        uint256 shares = vault.deposit(deposited / 2, ONBEHALF);
        vault.deposit(deposited / 2, SUPPLIER);
        vm.stopPrank();

        assets = bound(assets, deposited / 2 + 1, vault.totalAssets());

        uint256 sharesBurnt = vault.previewWithdraw(assets);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ONBEHALF, shares, sharesBurnt)
        );
        vm.prank(ONBEHALF);
        vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testWithdrawMoreThanTotalAssets(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assets = bound(assets, deposited + 1, type(uint256).max / (deposited + 1));

        vm.prank(ONBEHALF);
        vm.expectRevert(ErrorsLib.NotEnoughLiquidity.selector);
        vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testWithdrawMoreThanBalanceAndLiquidity(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        vault.deposit(deposited, ONBEHALF);

        assets = bound(assets, deposited + 1, type(uint256).max / (deposited + 1));

        collateralToken.setBalance(BORROWER, MAX_SANE_AMOUNT);

        // Borrow liquidity.
        vm.startPrank(BORROWER);
        collateralVault.deposit(type(uint256).max, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(1, BORROWER);

        vm.startPrank(ONBEHALF);
        vm.expectRevert(ErrorsLib.NotEnoughLiquidity.selector);
        vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testTransfer(uint256 deposited, uint256 toTransfer) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 minted = vault.deposit(deposited, ONBEHALF);

        toTransfer = bound(toTransfer, 0, minted);

        vm.prank(ONBEHALF);
        vault.transfer(RECEIVER, toTransfer);

        assertEq(vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER)");
        assertEq(vault.balanceOf(ONBEHALF), minted - toTransfer, "balanceOf(ONBEHALF)");
        assertEq(vault.balanceOf(RECEIVER), toTransfer, "balanceOf(RECEIVER)");
    }

    function testMaxWithdraw(uint256 depositedAssets, uint256 borrowedAssets) public {
        depositedAssets = bound(depositedAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        borrowedAssets = bound(borrowedAssets, MIN_TEST_ASSETS, depositedAssets);

        loanToken.setBalance(SUPPLIER, depositedAssets);

        vm.prank(SUPPLIER);
        vault.deposit(depositedAssets, ONBEHALF);

        collateralToken.setBalance(BORROWER, MAX_SANE_AMOUNT);

        vm.startPrank(BORROWER);
        collateralVault.deposit(type(uint256).max, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(borrowedAssets, BORROWER);

        assertEq(vault.maxWithdraw(ONBEHALF), depositedAssets - borrowedAssets, "maxWithdraw(ONBEHALF)");
    }

    function testMaxWithdrawWithUntrackedBalance(
        uint256 depositedAssets,
        uint256 borrowedAssets,
        uint256 marketIndex,
        uint256 untrackedAssets
    ) public {
        uint256 cap = MAX_TEST_ASSETS / 2;
        _setCap(allMarkets[0], cap);

        depositedAssets = bound(depositedAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        borrowedAssets = bound(borrowedAssets, MIN_TEST_ASSETS, UtilsLib.min(depositedAssets, cap));
        marketIndex = bound(marketIndex, 0, vault.supplyQueueLength() - 1);
        untrackedAssets = bound(untrackedAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        IERC4626 market = IERC4626(vault.supplyQueue(marketIndex));

        loanToken.setBalance(SUPPLIER, depositedAssets + untrackedAssets);

        vm.startPrank(SUPPLIER);
        vault.deposit(depositedAssets, ONBEHALF);

        // deposit directly to strategy for vault - untracked shares balance
        loanToken.approve(address(market), untrackedAssets);
        market.deposit(untrackedAssets, address(vault));

        collateralToken.setBalance(BORROWER, MAX_SANE_AMOUNT);

        vm.startPrank(BORROWER);
        collateralVault.deposit(type(uint256).max, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(borrowedAssets, BORROWER);

        uint256 expectedValue = market == allMarkets[0]
            ? UtilsLib.min(depositedAssets, depositedAssets - borrowedAssets + untrackedAssets)
            : depositedAssets - borrowedAssets;
        assertEq(vault.maxWithdraw(ONBEHALF), expectedValue, "maxWithdraw(ONBEHALF)");
    }

    function testMaxDeposit() public {
        _setCap(allMarkets[0], 1 ether);

        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = allMarkets[0];

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, 1 ether);
        collateralToken.setBalance(BORROWER, 2 ether);

        vm.prank(SUPPLIER);
        allMarkets[0].deposit(1 ether, SUPPLIER);

        vm.startPrank(BORROWER);
        collateralVault.deposit(2 ether, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(1 ether, BORROWER);
        vm.stopPrank();

        _forward(1_000);

        loanToken.setBalance(SUPPLIER, 2 ether);

        vm.prank(SUPPLIER);
        vault.deposit(1 ether, ONBEHALF);

        // since exchange rate in the market is >1, deposit will lose 1 wei due to rounding,
        // which reports max deposit as 1. It's not consumable though on Euler vaults,
        // due to zero shares error. The 1 wei is recorded in lostAssets, so caps are reached.
        assertEq(vault.maxDeposit(SUPPLIER), 1);

        vm.prank(SUPPLIER);
        vm.expectRevert(ErrorsLib.AllCapsReached.selector);
        vault.deposit(1, ONBEHALF);
    }

    function testMaxDepositWithZeroShares() public {
        // The vault will receive a deposit into a strategy which accrues interest.
        // Set the cap to 1 wei above total assets after interest is accrued.
        // This 1 wei would throw ZeroShares if deposited, therefore maxDeposit should return 0 instead
        uint256 expectedAccruedInterest = 1359118751534;
        uint256 cap = 1 ether + expectedAccruedInterest + 1;
        _setCap(allMarkets[0], cap);

        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = allMarkets[0];

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, 3 ether);
        collateralToken.setBalance(BORROWER, 2 ether);

        vm.startPrank(SUPPLIER);
        allMarkets[0].deposit(1 ether, SUPPLIER);
        vault.deposit(1 ether, ONBEHALF);

        vm.startPrank(BORROWER);
        collateralVault.deposit(2 ether, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));

        _toEVault(allMarkets[0]).borrow(1 ether, BORROWER);
        vm.stopPrank();

        _forward(1_000);

        // max deposit is 0
        assertEq(vault.maxDeposit(SUPPLIER), 0);
        // although cap still allows 1 wei
        assertEq(vault.totalAssets(), cap - 1);
        // because depositing 1 wei would throw zero shares
        vm.prank(SUPPLIER);
        vm.expectRevert(ErrorsLib.ZeroShares.selector);
        vault.deposit(1, ONBEHALF);
    }
}
