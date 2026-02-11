// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {StableWrapper} from "../../src/StableWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Base} from "./Base.t.sol";

/************************************************
 * INITIATE WITHDRAW TESTS
 ***********************************************/
contract StableWrapperInitiateWithdrawTest is Base {
    /************************************************
     *  INITIATE WITHDRAW FROM VAULT
     ***********************************************/
    function test_RevertIfAmountIsZero_Vault() public {
        depositFromAddyAndRollEpoch(depositor1, startingBal);
        vm.startPrank(keeper);
        vm.expectRevert(StableWrapper.AmountMustBeGreaterThanZero.selector);
        stableWrapper.initiateWithdrawalFromVault(depositor1, 0);
        vm.stopPrank();

        assertNoStateChangeAfterRevert_Vault(depositor1, startingBal);
    }

    function test_RevertIfWithdrawingWithZeroDeposit_Vault(
        uint224 _amount
    ) public {
        vm.assume(_amount != 0);
        vm.startPrank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(stableWrapper),
                0,
                uint256(_amount)
            )
        );
        stableWrapper.initiateWithdrawalFromVault(depositor1, _amount);
        vm.stopPrank();

        assertNoStateChangeAfterRevert_Vault(depositor1, 0);
    }

    function test_RevertIfCallerIsNotTheKeeper_Vault(address _caller) public {
        vm.assume(_caller != keeper);
        vm.assume(_caller != address(0));
        depositFromAddyAndRollEpoch(depositor1, startingBal);
        vm.startPrank(_caller);
        vm.expectRevert(StableWrapper.NotKeeper.selector);
        stableWrapper.initiateWithdrawalFromVault(
            depositor1,
            uint224(startingBal)
        );
        vm.stopPrank();

        assertNoStateChangeAfterRevert_Vault(depositor1, startingBal);
    }

    function test_SuccessfullFullWithdrawalInitFromVault_Vault(
        uint224 _amount
    ) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);
        depositFromAddyAndRollEpoch(depositor1, _amount);
        vm.prank(keeper);
        stableWrapper.transfer(address(stableWrapper), _amount);
        vm.prank(keeper);
        stableWrapper.initiateWithdrawalFromVault(depositor1, _amount);

        (uint224 receiptAmount, uint32 receiptEpoch) = stableWrapper
            .withdrawalReceipts(depositor1);

        vm.assertEq(receiptAmount, _amount);
        vm.assertEq(receiptEpoch, 2);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(stableWrapper.totalSupply(), 0);
        vm.assertEq(stableWrapper.balanceOf(address(owner)), 0);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
    }

    function test_SuccessfullPartialWithdrawalInitFromVault_Vault(
        uint224 _amount
    ) public {
        vm.assume(_amount >= 2);
        vm.assume(_amount <= startingBal);
        depositFromAddyAndRollEpoch(depositor1, _amount);
        vm.prank(keeper);
        stableWrapper.transfer(address(stableWrapper), _amount - 1);
        vm.prank(keeper);
        stableWrapper.initiateWithdrawalFromVault(depositor1, _amount - 1);

        (uint224 receiptAmount, uint32 receiptEpoch) = stableWrapper
            .withdrawalReceipts(depositor1);

        vm.assertEq(receiptAmount, _amount - 1);
        vm.assertEq(receiptEpoch, 2);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(stableWrapper.totalSupply(), 1);
        vm.assertEq(stableWrapper.balanceOf(address(keeper)), 1);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
    }

    /************************************************
     *  INITIATE WITHDRAW REGULAR
     ***********************************************/

    function test_RevertIfAmountIsZero_Regular() public {
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        depositFromAddyAndRollEpoch(depositor1, startingBal);
        vm.startPrank(depositor1);
        vm.expectRevert(StableWrapper.AmountMustBeGreaterThanZero.selector);
        stableWrapper.initiateWithdrawal(0);
        vm.stopPrank();

        assertNoStateChangeAfterRevert_Vault(depositor1, startingBal);
    }

    function test_RevertIfWithdrawingWithZeroDeposit_Regular(
        uint224 _amount
    ) public {
        vm.assume(_amount != 0);
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        vm.startPrank(depositor1);
        vm.expectRevert(StableWrapper.InsufficientBalance.selector);
        stableWrapper.initiateWithdrawal(_amount);
        vm.stopPrank();

        assertNoStateChangeAfterRevert_Vault(depositor1, 0);
    }

    function test_SuccessfullFullWithdrawalInit_Regular(
        uint224 _amount
    ) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        depositFromAddyAndRollEpoch(depositor1, _amount);
        vm.prank(keeper);
        stableWrapper.transfer(address(depositor1), _amount);
        vm.prank(depositor1);
        stableWrapper.initiateWithdrawal(_amount);

        (uint224 receiptAmount, uint32 receiptEpoch) = stableWrapper
            .withdrawalReceipts(depositor1);

        vm.assertEq(receiptAmount, _amount);
        vm.assertEq(receiptEpoch, 2);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(stableWrapper.totalSupply(), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), 0);

        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
    }

    function test_SuccessfullPartialWithdrawalInit_Regular(
        uint224 _amount
    ) public {
        vm.assume(_amount >= 2);
        vm.assume(_amount <= startingBal);
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        depositFromAddyAndRollEpoch(depositor1, _amount);
        vm.prank(keeper);
        stableWrapper.transfer(address(depositor1), _amount);
        vm.prank(depositor1);
        stableWrapper.initiateWithdrawal(_amount - 1);

        (uint224 receiptAmount, uint32 receiptEpoch) = stableWrapper
            .withdrawalReceipts(depositor1);

        vm.assertEq(receiptAmount, _amount - 1);
        vm.assertEq(receiptEpoch, 2);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 1);
        vm.assertEq(stableWrapper.totalSupply(), 1);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), 0);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
    }
}
