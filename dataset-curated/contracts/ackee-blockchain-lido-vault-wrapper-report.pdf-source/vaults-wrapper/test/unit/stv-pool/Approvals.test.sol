// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

contract ApprovalsTest is Test, SetupStvPool {
    function setUp() public override {
        super.setUp();

        // Setup: deposit ETH for users
        vm.prank(userAlice);
        pool.depositETH{value: 10 ether}(userAlice, address(0));
    }

    function test_Approve_SetsAllowance() public {
        uint256 amount = 5 * 10 ** pool.decimals();

        vm.prank(userAlice);
        pool.approve(userBob, amount);

        assertEq(pool.allowance(userAlice, userBob), amount);
    }

    function test_Approve_OverwritesExisting() public {
        uint256 firstAmount = 5 * 10 ** pool.decimals();
        uint256 secondAmount = 10 * 10 ** pool.decimals();

        vm.startPrank(userAlice);
        pool.approve(userBob, firstAmount);
        assertEq(pool.allowance(userAlice, userBob), firstAmount);

        pool.approve(userBob, secondAmount);
        assertEq(pool.allowance(userAlice, userBob), secondAmount);
        vm.stopPrank();
    }

    function test_Approve_EmitsEvent() public {
        uint256 amount = 5 * 10 ** pool.decimals();

        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(userAlice, userBob, amount);

        vm.prank(userAlice);
        pool.approve(userBob, amount);
    }

    function test_Approve_MaxUint256() public {
        uint256 maxAmount = type(uint256).max;

        vm.prank(userAlice);
        pool.approve(userBob, maxAmount);

        assertEq(pool.allowance(userAlice, userBob), maxAmount);
    }

    function test_Approve_WorksWithUnassignedLiability() public {
        // Add unassigned liability
        dashboard.mock_increaseLiability(100);

        // Approve should still work even with unassigned liability
        uint256 amount = 1 * 10 ** pool.decimals();

        vm.prank(userAlice);
        pool.approve(userBob, amount);

        assertEq(pool.allowance(userAlice, userBob), amount);
    }
}
