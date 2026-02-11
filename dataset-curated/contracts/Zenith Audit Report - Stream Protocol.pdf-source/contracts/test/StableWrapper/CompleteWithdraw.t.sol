// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {StableWrapper} from "../../src/StableWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Base} from "./Base.t.sol";

/************************************************
 * COMPLETE WITHDRAW TESTS
 ***********************************************/
contract StableWrapperCompleteWithdrawTest is Base {
    function test_RevertIfNoWithdrawalReceipt(uint224 _amount) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);

        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);

        depositFromAddyAndRollEpoch(depositor1, _amount);

        vm.prank(keeper);
        stableWrapper.transfer(depositor1, _amount);

        vm.prank(owner);
        stableWrapper.processWithdrawals();

        vm.startPrank(depositor1);
        vm.expectRevert(StableWrapper.AmountMustBeGreaterThanZero.selector);
        stableWrapper.completeWithdrawal(depositor1);
        vm.stopPrank();

        assertEq(stableWrapper.balanceOf(depositor1), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(stableWrapper.currentEpoch(), 3);
        assertEq(usdc.balanceOf(address(stableWrapper)), 0);
    }

    function test_RevertIfEpochHasNotPassed(uint224 _amount) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);

        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);

        depositFromAddyAndRollEpoch(depositor1, _amount);

        vm.prank(keeper);
        stableWrapper.transfer(depositor1, _amount);

        vm.prank(depositor1);
        stableWrapper.initiateWithdrawal(_amount);

        vm.startPrank(depositor1);
        vm.expectRevert(
            StableWrapper.CannotCompleteWithdrawalInSameEpoch.selector
        );
        stableWrapper.completeWithdrawal(depositor1);
        vm.stopPrank();

        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(stableWrapper.totalSupply(), 0);
        assertEq(stableWrapper.currentEpoch(), 2);
        assertEq(usdc.balanceOf(address(stableWrapper)), 0);
    }
    function test_SuccessfullBasicCompleteWithdraw(uint224 _amount) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);

        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);

        depositFromAddyAndRollEpoch(depositor1, _amount);

        vm.prank(keeper);
        stableWrapper.transfer(depositor1, _amount);

        vm.prank(depositor1);
        stableWrapper.initiateWithdrawal(_amount);

        vm.startPrank(owner);
        usdc.approve(address(stableWrapper), _amount);
        stableWrapper.processWithdrawals();
        vm.stopPrank();

        vm.prank(depositor1);
        stableWrapper.completeWithdrawal(depositor1);

        (uint224 receiptAmont, uint32 receiptEpoch) = stableWrapper
            .withdrawalReceipts(depositor1);

        assertEq(receiptAmont, 0);
        assertEq(receiptEpoch, 0);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(stableWrapper.totalSupply(), 0);
        assertEq(stableWrapper.currentEpoch(), 3);
        assertEq(usdc.balanceOf(depositor1), startingBal);
        assertEq(usdc.balanceOf(address(stableWrapper)), 0);
    }

    function test_SuccessfullOtherAddyCompleteWithdraw(uint224 _amount) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);

        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);

        depositFromAddyAndRollEpoch(depositor1, _amount);

        vm.prank(keeper);
        stableWrapper.transfer(depositor1, _amount);

        vm.prank(depositor1);
        stableWrapper.initiateWithdrawal(_amount);

        vm.startPrank(owner);
        usdc.approve(address(stableWrapper), _amount);
        stableWrapper.processWithdrawals();
        vm.stopPrank();

        vm.prank(depositor1);
        stableWrapper.completeWithdrawal(depositor2);

        (uint224 receiptAmont, uint32 receiptEpoch) = stableWrapper
            .withdrawalReceipts(depositor1);

        assertEq(receiptAmont, 0);
        assertEq(receiptEpoch, 0);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(stableWrapper.totalSupply(), 0);
        assertEq(stableWrapper.currentEpoch(), 3);
        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        assertEq(usdc.balanceOf(address(stableWrapper)), 0);
        assertEq(usdc.balanceOf(depositor2), startingBal + _amount);
    }
}
