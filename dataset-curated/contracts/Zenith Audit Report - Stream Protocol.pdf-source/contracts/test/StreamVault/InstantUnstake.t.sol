// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Base} from "./Base.t.sol";
import {Vault} from "../../src/lib/Vault.sol";
import {StreamVault} from "../../src/StreamVault.sol";

/************************************************
 *  ISNTANT UNSTAKE TESTS
 ***********************************************/
contract StreamVaultInstantUnstakeTest is Base {
    /************************************************
     *  INSTANT UNSTAKE AND WITHDRAW FROM VAULT TESTS
     ***********************************************/

    function test_RevertIfAmountIsZero_Vault(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAssets(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.AmountMustBeGreaterThanZero.selector);
        streamVault.instantUnstakeAndWithdraw(0);
        vm.stopPrank();

        assertStakeReceipt(depositor1, 1, _amount, 0);
        vm.assertEq(streamVault.balanceOf(depositor1), 0);
        vm.assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        vm.assertEq(stableWrapper.totalSupply(), _amount);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }

    function test_RevertIfInstantUnstakingInNotTheSameRound_Vault(
        uint104 _amount
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.RoundMismatch.selector);
        streamVault.instantUnstakeAndWithdraw(_amount);
        vm.stopPrank();
    }

    function test_RevertIfTryingToUnstakeMoreThanStaked(
        uint104 _amount
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAssets(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.AmountExceedsReceipt.selector);
        streamVault.instantUnstakeAndWithdraw(_amount + 1);
        vm.stopPrank();
    }

    function test_SuccessfullInstantUnstakeAndWithdraw_Full_Vault(
        uint104 _amount
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAssets(depositor1, depositor1, _amount);
        assertStakeReceipt(depositor1, 1, _amount, 0);
        vm.prank(depositor1);
        streamVault.instantUnstakeAndWithdraw(_amount);
        assertStakeReceipt(depositor1, 1, 0, 0);
        assertVaultState(1, 0);
        vm.assertEq(streamVault.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        vm.assertEq(stableWrapper.balanceOf(address(streamVault)), 0);
        vm.assertEq(stableWrapper.totalSupply(), 0);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }

    function test_SuccessfullInstantUnstakeAndWithdraw_Partial_Vault(
        uint104 _amount
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAssets(depositor1, depositor1, _amount);
        assertStakeReceipt(depositor1, 1, _amount, 0);
        vm.prank(depositor1);
        streamVault.instantUnstakeAndWithdraw(_amount - 1);
        assertStakeReceipt(depositor1, 1, 1, 0);
        assertVaultState(1, 1);
        vm.assertEq(streamVault.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        vm.assertEq(stableWrapper.balanceOf(address(streamVault)), 1);
        vm.assertEq(stableWrapper.totalSupply(), 1);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }

    /************************************************
     *  INSTANT UNSTAKE AND WITHDRAW TESTS
     ***********************************************/

    function test_RevertIfAllowIndependenceIsFalse(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAssets(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.IndependenceNotAllowed.selector);
        streamVault.instantUnstake(_amount);
        vm.stopPrank();
    }

    function test_SuccessfullInstantUnstake_Full(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.prank(owner);
        streamVault.setAllowIndependence(true);

        stakeAssets(depositor1, depositor1, _amount);
        assertStakeReceipt(depositor1, 1, _amount, 0);
        vm.prank(depositor1);
        streamVault.instantUnstake(_amount);

        assertStakeReceipt(depositor1, 1, 0, 0);
        assertVaultState(1, 0);
        vm.assertEq(streamVault.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        vm.assertEq(stableWrapper.balanceOf(address(streamVault)), 0);
        vm.assertEq(stableWrapper.totalSupply(), _amount);
        vm.assertEq(stableWrapper.balanceOf(depositor1), _amount);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }

    function test_SuccessfullInstantUnstake_Partial(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.prank(owner);
        streamVault.setAllowIndependence(true);

        stakeAssets(depositor1, depositor1, _amount);
        assertStakeReceipt(depositor1, 1, _amount, 0);
        vm.prank(depositor1);
        streamVault.instantUnstake(_amount - 1);

        assertStakeReceipt(depositor1, 1, 1, 0);
        assertVaultState(1, 1);
        vm.assertEq(streamVault.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        vm.assertEq(stableWrapper.balanceOf(address(streamVault)), 1);
        vm.assertEq(stableWrapper.totalSupply(), _amount);
        vm.assertEq(stableWrapper.balanceOf(depositor1), _amount - 1);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }
}
