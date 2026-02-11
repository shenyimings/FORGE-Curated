// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Base} from "./Base.t.sol";
import {Vault} from "../../src/lib/Vault.sol";
import {StreamVault} from "../../src/StreamVault.sol";

/************************************************
 *  REDEEM TESTS
 ***********************************************/
contract StreamVaultUnstakeTest is Base {
    function test_RevertIfRedeemingZeroShares(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.AmountMustBeGreaterThanZero.selector);
        streamVault.redeem(0);
        vm.stopPrank();
    }

    function test_RevertIfInsufficientUnredeemedShares(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.InsufficientUnredeemedShares.selector);
        streamVault.redeem(_amount + 1);
        vm.stopPrank();
    }

    function test_SuccessfulMaxRedeem_RegularFunc(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.prank(depositor1);
        streamVault.redeem(_amount);

        assertVaultState(2, 0);
        assertStakeReceipt(depositor1, 1, 0, 0);
        assertEq(streamVault.balanceOf(depositor1), _amount);
        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        assertEq(streamVault.omniTotalSupply(), _amount);

        assertShares(depositor1, _amount);
        assertSharesHeldByAccount(depositor1, _amount);
        assertSharesHeldByVault(depositor1, 0);
    }

    function test_SuccessfulMaxRedeem_MaxFunc(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.prank(depositor1);
        streamVault.maxRedeem();

        assertVaultState(2, 0);
        assertStakeReceipt(depositor1, 1, 0, 0);
        assertEq(streamVault.balanceOf(depositor1), _amount);
        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        assertEq(streamVault.balanceOf(address(streamVault)), 0);
        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        assertEq(streamVault.omniTotalSupply(), _amount);

        assertShares(depositor1, _amount);
        assertSharesHeldByAccount(depositor1, _amount);
        assertSharesHeldByVault(depositor1, 0);
    }

    function test_SuccessfulPartialRedeem(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.prank(depositor1);
        streamVault.redeem(_amount - 1);

        assertVaultState(2, 0);
        assertStakeReceipt(depositor1, 1, 0, 1);
        assertEq(streamVault.balanceOf(depositor1), _amount - 1);
        assertEq(streamVault.balanceOf(address(streamVault)), 1);
        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(stableWrapper.balanceOf(depositor1), 0);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        assertEq(streamVault.omniTotalSupply(), _amount);

        assertShares(depositor1, _amount);
        assertSharesHeldByAccount(depositor1, _amount - 1);
        assertSharesHeldByVault(depositor1, 1);
    }
}
