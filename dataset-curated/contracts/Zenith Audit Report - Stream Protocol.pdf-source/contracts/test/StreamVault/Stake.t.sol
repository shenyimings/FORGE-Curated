// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Base} from "./Base.t.sol";
import {Vault} from "../../src/lib/Vault.sol";
import {StreamVault} from "../../src/StreamVault.sol";

/************************************************
 *  STAKE TESTS
 ***********************************************/
contract StreamVaultStakeTest is Base {
    /************************************************
     *  DEPOSIT AND STAKE TESTS
     ***********************************************/
    function test_RevertIfDepositExceedsCap() public {
        usdc.mint(depositor1, cap + 1);
        vm.startPrank(depositor1);
        usdc.approve(address(stableWrapper), cap + 1);
        vm.expectRevert(StreamVault.CapExceeded.selector);
        streamVault.depositAndStake(cap + 1, depositor1);
        vm.stopPrank();

        assertBaseState();
    }

    function test_RevertIfDepositIsShortOfMinSupply() public {
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.MinimumSupplyNotMet.selector);
        streamVault.depositAndStake(minSupply - 1, depositor1);
        vm.stopPrank();
        assertBaseState();
    }

    function test_SuccessfullDepositAndStake_Receipt(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.prank(depositor1);
        streamVault.depositAndStake(_amount, depositor1);

        assertEq(streamVault.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);

        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);

        assertVaultState(1, _amount);
        assertStakeReceipt(depositor1, 1, _amount, 0);
    }

    function test_SuccessfullDepositAndStake_WithRoll(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.prank(depositor1);
        streamVault.depositAndStake(_amount, depositor1);

        vm.prank(owner);
        streamVault.rollToNextRound(0, true);

        assertEq(streamVault.balanceOf(depositor1), 0);
        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        assertEq(streamVault.omniTotalSupply(), _amount);
        assertEq(streamVault.balanceOf(address(streamVault)), _amount);

        assertVaultState(2, 0);
        assertStakeReceipt(depositor1, 1, _amount, 0);
        assertShares(depositor1, _amount);
        assertAccountVaultBalance(depositor1, _amount);
    }

    function test_SuccessfullDepositAndStake_WithRoll_WithMaxRedeem(
        uint104 _amount
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.prank(depositor1);
        streamVault.depositAndStake(_amount, depositor1);

        vm.prank(owner);
        streamVault.rollToNextRound(0, true);

        vm.prank(depositor1);
        streamVault.maxRedeem();

        assertEq(streamVault.balanceOf(depositor1), _amount);
        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        assertEq(streamVault.omniTotalSupply(), _amount);
        assertEq(streamVault.balanceOf(address(streamVault)), 0);

        assertVaultState(2, 0);
        assertStakeReceipt(depositor1, 1, 0, 0);
        assertShares(depositor1, _amount);
        assertAccountVaultBalance(depositor1, _amount);
    }

    function test_SuccessfullDepositAndStake_WithRoll_WithPartialRedeem(
        uint104 _amount
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.prank(depositor1);
        streamVault.depositAndStake(_amount, depositor1);

        vm.prank(owner);
        streamVault.rollToNextRound(0, true);

        vm.prank(depositor1);
        streamVault.redeem(_amount - 1);

        assertEq(streamVault.balanceOf(depositor1), _amount - 1);
        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        assertEq(streamVault.omniTotalSupply(), _amount);
        assertEq(streamVault.balanceOf(address(streamVault)), 1);

        assertVaultState(2, 0);
        assertStakeReceipt(depositor1, 1, 0, 1);
        assertShares(depositor1, _amount);
        assertAccountVaultBalance(depositor1, _amount);
    }

    /************************************************
     *  REGULAR STAKE TESTS
     ***********************************************/
    function test_ReverIfNotAllowedIndependence(
        uint104 _amount,
        address _creditor
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_creditor != address(0));
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.IndependenceNotAllowed.selector);
        streamVault.stake(_amount, _creditor);
        vm.stopPrank();

        assertBaseState();
    }

    function test_RevertIfStakeAmountIsZero(address _creditor) public {
        vm.assume(_creditor != address(0));
        vm.startPrank(owner);
        streamVault.setAllowIndependence(true);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.AmountMustBeGreaterThanZero.selector);
        streamVault.stake(0, _creditor);
        vm.stopPrank();

        assertBaseState();
    }

    function test_RevertIfCreditorIsZeroAddress(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.startPrank(owner);
        streamVault.setAllowIndependence(true);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.AddressMustBeNonZero.selector);
        streamVault.stake(_amount, address(0));
        vm.stopPrank();

        assertBaseState();
    }

    function test_SuccessfullAssetTransferWhenStaking_Self(
        uint104 _amount
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        vm.prank(owner);
        streamVault.setAllowIndependence(true);

        vm.startPrank(depositor1);
        stableWrapper.deposit(depositor1, _amount);
        stableWrapper.approve(address(streamVault), _amount);
        streamVault.stake(_amount, depositor1);

        assertEq(streamVault.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);

        assertVaultState(1, _amount);
        assertStakeReceipt(depositor1, 1, _amount, 0);
    }
}
