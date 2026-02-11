// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";

contract DepositTest is Test, SetupStvPool {
    // Base deposits

    function test_Deposit_EmitsCorrectEvent() public {
        uint256 amount = 1 ether;
        uint256 expectedStv = pool.previewDeposit(amount);

        vm.expectEmit(true, true, true, true);
        emit StvPool.Deposit(userAlice, userAlice, address(0), amount, expectedStv);

        vm.prank(userAlice);
        pool.depositETH{value: amount}(userAlice, address(0));
    }

    function test_Deposit_WithReferral_EmitsEventWithReferral() public {
        uint256 amount = 1 ether;
        uint256 expectedStv = pool.previewDeposit(amount);
        address referral = makeAddr("referral");

        vm.expectEmit(true, true, true, true);
        emit StvPool.Deposit(userAlice, userAlice, referral, amount, expectedStv);

        vm.prank(userAlice);
        pool.depositETH{value: amount}(userAlice, referral);
    }

    function test_Deposit_ToAnotherRecipient_MintsToRecipient() public {
        uint256 amount = 1 ether;
        uint256 bobBalanceBefore = pool.balanceOf(userBob);

        vm.prank(userAlice);
        pool.depositETH{value: amount}(userBob, address(0));

        assertGt(pool.balanceOf(userBob), bobBalanceBefore);
        assertEq(pool.balanceOf(userAlice), 0);
    }

    function test_Deposit_CallsDashboardFund() public {
        uint256 amount = 1 ether;

        vm.expectCall(address(dashboard), amount, abi.encodeWithSelector(dashboard.fund.selector));

        vm.prank(userAlice);
        pool.depositETH{value: amount}(userAlice, address(0));
    }

    function test_Deposit_FundsTransferredToDashboard() public {
        uint256 amount = 1 ether;
        address stakingVault = dashboard.stakingVault();
        uint256 vaultBalanceBefore = address(stakingVault).balance;

        vm.prank(userAlice);
        pool.depositETH{value: amount}(userAlice, address(0));

        assertEq(address(stakingVault).balance, vaultBalanceBefore + amount);
    }

    // Edge cases

    function test_Deposit_MinimalAmount_OneWei() public {
        uint256 amount = 1 wei;
        uint256 balanceBefore = pool.balanceOf(userAlice);

        vm.prank(userAlice);
        pool.depositETH{value: amount}(userAlice, address(0));

        assertGt(pool.balanceOf(userAlice), balanceBefore);
    }

    function test_Deposit_HugeAmount() public {
        uint256 amount = 100_000 ether;
        vm.deal(userAlice, amount);

        vm.prank(userAlice);
        pool.depositETH{value: amount}(userAlice, address(0));

        assertGt(pool.balanceOf(userAlice), 0);
    }

    function test_Deposit_MultipleSmallDeposits_Accumulate() public {
        uint256 depositCount = 10;
        uint256 depositAmount = 0.1 ether;
        uint256 balanceBefore = pool.balanceOf(userAlice);

        for (uint256 i = 0; i < depositCount; i++) {
            vm.prank(userAlice);
            pool.depositETH{value: depositAmount}(userAlice, address(0));
        }

        uint256 balanceAfter = pool.balanceOf(userAlice);
        assertEq(balanceAfter - balanceBefore, pool.previewDeposit(depositAmount * depositCount));
    }

    // Revert cases

    function test_Deposit_RevertOn_ZeroAmount() public {
        vm.prank(userAlice);
        vm.expectRevert(StvPool.ZeroDeposit.selector);
        pool.depositETH{value: 0}(userAlice, address(0));
    }

    function test_Deposit_RevertOn_ZeroRecipient() public {
        vm.prank(userAlice);
        vm.expectRevert(StvPool.InvalidRecipient.selector);
        pool.depositETH{value: 1 ether}(address(0), address(0));
    }

    // Receive function

    function test_Receive_AutoDeposits() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = pool.balanceOf(userAlice);

        vm.prank(userAlice);
        (bool success,) = address(pool).call{value: amount}("");
        assertTrue(success);

        assertGt(pool.balanceOf(userAlice), balanceBefore);
    }

    function test_Receive_MintsToSender() public {
        uint256 amount = 1 ether;
        uint256 expectedStv = pool.previewDeposit(amount);

        vm.prank(userAlice);
        (bool success,) = address(pool).call{value: amount}("");
        assertTrue(success);

        assertEq(pool.balanceOf(userAlice), expectedStv);
    }

    function test_Receive_EmitsEvent() public {
        uint256 amount = 1 ether;
        uint256 expectedStv = pool.previewDeposit(amount);

        vm.expectEmit(true, true, true, true);
        emit StvPool.Deposit(userAlice, userAlice, address(0), amount, expectedStv);

        vm.prank(userAlice);
        (bool success,) = address(pool).call{value: amount}("");
        assertTrue(success);
    }
}
