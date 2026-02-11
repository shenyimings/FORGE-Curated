// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Base} from "./Base.t.sol";
import {Vault} from "../../src/lib/Vault.sol";
import {StreamVault} from "../../src/StreamVault.sol";

/************************************************
 *  UNSTAKE TESTS
 ***********************************************/
contract StreamVaultUnstakeTest is Base {
    /************************************************
     *  UNSTAKE AND WITHDRAW TESTS
     ***********************************************/
    function test_RevertIfSharesToUnstakeIsZero_Vault(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.AmountMustBeGreaterThanZero.selector);
        streamVault.unstakeAndWithdraw(0);
        vm.stopPrank();

        assertOneRollBaseState(_amount, 2);
    }

    function test_RevertIfUnstakingInRoundOne_Vault(
        uint104 _amount,
        uint104 _shares
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_shares <= _amount);
        vm.assume(_shares > 0);
        stakeAssets(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.RoundMustBeGreaterThanOne.selector);
        streamVault.unstakeAndWithdraw(_shares);
        vm.stopPrank();

        vm.assertEq(streamVault.balanceOf(depositor1), 0);
        vm.assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        vm.assertEq(stableWrapper.totalSupply(), _amount);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        assertVaultState(1, _amount);
    }

    function test_UnstakeAndWithdrawSuccess_Vault(
        uint104 _amount,
        uint104 _shares
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_shares <= _amount);
        vm.assume(_shares > 0);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.prank(depositor1);
        streamVault.unstakeAndWithdraw(_shares);

        vm.assertEq(streamVault.balanceOf(depositor1), _amount - _shares);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        vm.assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount - _shares
        );
        vm.assertEq(stableWrapper.totalSupply(), _amount - _shares);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        vm.assertEq(streamVault.omniTotalSupply(), _amount - _shares);
        assertVaultState(2, 0);
    }

    function test_UnstakeAndWithdrawSuccess_WithFullRedeem_Vault(
        uint104 _amount,
        uint104 _shares
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_shares <= _amount);
        vm.assume(_shares > 0);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        streamVault.maxRedeem();
        streamVault.unstakeAndWithdraw(_shares);

        vm.assertEq(streamVault.balanceOf(depositor1), _amount - _shares);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        vm.assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount - _shares
        );
        vm.assertEq(stableWrapper.totalSupply(), _amount - _shares);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        vm.assertEq(streamVault.omniTotalSupply(), _amount - _shares);
        assertVaultState(2, 0);
    }

    function test_UnstakeAndWithdrawSuccess_WithPartialRedeem_Vault(
        uint104 _amount,
        uint104 _shares
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_shares <= _amount);
        vm.assume(_shares > 2);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.startPrank(depositor1);
        streamVault.redeem(_shares - 1);
        streamVault.unstakeAndWithdraw(_shares);

        vm.assertEq(streamVault.balanceOf(depositor1), _amount - _shares);
        vm.assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        vm.assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount - _shares
        );
        vm.assertEq(stableWrapper.totalSupply(), _amount - _shares);
        vm.assertEq(stableWrapper.balanceOf(depositor1), 0);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        vm.assertEq(streamVault.omniTotalSupply(), _amount - _shares);
        assertVaultState(2, 0);
    }

    /************************************************
     *  UNSTAKE  TESTS
     ***********************************************/
    function test_RevertIfIndependeceNotAllowed() public {
        vm.startPrank(depositor1);
        vm.expectRevert(StreamVault.IndependenceNotAllowed.selector);
        streamVault.unstake(0);
        vm.stopPrank();
        assertBaseState();
    }

    function test_UnstakeSuccessfull(uint104 _amount, uint104 _shares) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_shares <= _amount);
        vm.assume(_shares > 0);
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.prank(owner);
        streamVault.setAllowIndependence(true);
        vm.prank(depositor1);
        streamVault.unstake(_shares);

        vm.assertEq(streamVault.balanceOf(depositor1), _amount - _shares);
        vm.assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount - _shares
        );
        vm.assertEq(stableWrapper.totalSupply(), _amount);
        vm.assertEq(stableWrapper.balanceOf(depositor1), _shares);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
        vm.assertEq(streamVault.omniTotalSupply(), _amount - _shares);
        assertVaultState(2, 0);
    }
}
