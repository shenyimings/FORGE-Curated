// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";

contract WithdrawalQueueTest is Test, SetupStvPool {
    // transferFromForWithdrawalQueue tests

    function test_TransferFromForWQ_OnlyCallableByWQ() public {
        pool.depositETH{value: 1 ether}(userAlice, address(0));

        vm.prank(userAlice);
        vm.expectRevert(StvPool.NotWithdrawalQueue.selector);
        pool.transferFromForWithdrawalQueue(userAlice, 1 ether);
    }

    function test_TransferFromForWQ_UpdatesBalances() public {
        pool.depositETH{value: 1 ether}(userAlice, address(0));
        uint256 stvAmount = pool.balanceOf(userAlice);

        uint256 aliceBalanceBefore = pool.balanceOf(userAlice);
        uint256 wqBalanceBefore = pool.balanceOf(withdrawalQueue);

        vm.prank(withdrawalQueue);
        pool.transferFromForWithdrawalQueue(userAlice, stvAmount);

        assertEq(pool.balanceOf(userAlice), aliceBalanceBefore - stvAmount);
        assertEq(pool.balanceOf(withdrawalQueue), wqBalanceBefore + stvAmount);
    }

    function test_TransferFromForWQ_EmitsTransferEvent() public {
        pool.depositETH{value: 1 ether}(userAlice, address(0));
        uint256 stvAmount = pool.balanceOf(userAlice);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(userAlice, withdrawalQueue, stvAmount);

        vm.prank(withdrawalQueue);
        pool.transferFromForWithdrawalQueue(userAlice, stvAmount);
    }

    // burnStvForWithdrawalQueue tests

    function test_BurnStvForWQ_OnlyCallableByWQ() public {
        vm.prank(userAlice);
        vm.expectRevert(StvPool.NotWithdrawalQueue.selector);
        pool.burnStvForWithdrawalQueue(1 ether);
    }

    function test_BurnStvForWQ_BurnsStv() public {
        // Transfer some stv to WQ first
        pool.depositETH{value: 1 ether}(userAlice, address(0));
        uint256 stvAmount = pool.balanceOf(userAlice);

        vm.prank(withdrawalQueue);
        pool.transferFromForWithdrawalQueue(userAlice, stvAmount);

        uint256 wqBalanceBefore = pool.balanceOf(withdrawalQueue);

        vm.prank(withdrawalQueue);
        pool.burnStvForWithdrawalQueue(stvAmount);

        assertEq(pool.balanceOf(withdrawalQueue), wqBalanceBefore - stvAmount);
    }

    function test_BurnStvForWQ_DecreasesTotalSupply() public {
        pool.depositETH{value: 1 ether}(userAlice, address(0));
        uint256 stvAmount = pool.balanceOf(userAlice);

        vm.prank(withdrawalQueue);
        pool.transferFromForWithdrawalQueue(userAlice, stvAmount);

        uint256 totalSupplyBefore = pool.totalSupply();

        vm.prank(withdrawalQueue);
        pool.burnStvForWithdrawalQueue(stvAmount);

        assertEq(pool.totalSupply(), totalSupplyBefore - stvAmount);
    }

    function test_BurnStvForWQ_RevertOn_NoBadDebt() public {
        // Setup: deposit and transfer to WQ
        pool.depositETH{value: 10 ether}(userAlice, address(0));
        uint256 stvAmount = pool.balanceOf(userAlice);

        vm.prank(withdrawalQueue);
        pool.transferFromForWithdrawalQueue(userAlice, stvAmount);

        // Create bad debt
        dashboard.mock_increaseLiability(steth.getSharesByPooledEth(pool.totalAssets()) + 1);

        vm.prank(withdrawalQueue);
        vm.expectRevert(StvPool.VaultInBadDebt.selector);
        pool.burnStvForWithdrawalQueue(stvAmount);
    }

    function test_BurnStvForWQ_RevertOn_NoUnassignedLiability() public {
        // Setup: deposit and transfer to WQ
        pool.depositETH{value: 1 ether}(userAlice, address(0));
        uint256 stvAmount = pool.balanceOf(userAlice);

        vm.prank(withdrawalQueue);
        pool.transferFromForWithdrawalQueue(userAlice, stvAmount);

        // Create unassigned liability
        dashboard.mock_increaseLiability(100);

        vm.prank(withdrawalQueue);
        vm.expectRevert(StvPool.UnassignedLiabilityOnVault.selector);
        pool.burnStvForWithdrawalQueue(stvAmount);
    }
}
