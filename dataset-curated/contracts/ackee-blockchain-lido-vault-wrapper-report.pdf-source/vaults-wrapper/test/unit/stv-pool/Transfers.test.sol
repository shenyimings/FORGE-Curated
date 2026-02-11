// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";

contract TransfersTest is Test, SetupStvPool {
    function setUp() public override {
        super.setUp();

        // Setup: deposit ETH for users
        vm.prank(userAlice);
        pool.depositETH{value: 10 ether}(userAlice, address(0));

        vm.prank(userBob);
        pool.depositETH{value: 5 ether}(userBob, address(0));
    }

    // Basic transfers

    function test_Transfer_BasicTransfer_UpdatesBalances() public {
        uint256 amount = 10 ** pool.decimals();
        uint256 aliceBalanceBefore = pool.balanceOf(userAlice);
        uint256 bobBalanceBefore = pool.balanceOf(userBob);

        vm.prank(userAlice);
        assertTrue(pool.transfer(userBob, amount));

        assertEq(pool.balanceOf(userAlice), aliceBalanceBefore - amount);
        assertEq(pool.balanceOf(userBob), bobBalanceBefore + amount);
    }

    function test_Transfer_ToSelf_NoChange() public {
        uint256 amount = 10 ** pool.decimals();
        uint256 balanceBefore = pool.balanceOf(userAlice);

        vm.prank(userAlice);
        assertTrue(pool.transfer(userAlice, amount));

        assertEq(pool.balanceOf(userAlice), balanceBefore);
    }

    function test_Transfer_FullBalance_EmptiesSender() public {
        uint256 aliceBalance = pool.balanceOf(userAlice);

        vm.prank(userAlice);
        assertTrue(pool.transfer(userBob, aliceBalance));

        assertEq(pool.balanceOf(userAlice), 0);
    }

    function test_Transfer_EmitsEvent() public {
        uint256 amount = 10 ** pool.decimals();

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(userAlice, userBob, amount);

        vm.prank(userAlice);
        assertTrue(pool.transfer(userBob, amount));
    }

    // TransferFrom

    function test_TransferFrom_WithApproval_Success() public {
        uint256 amount = 10 ** pool.decimals();

        vm.prank(userAlice);
        pool.approve(address(this), amount);

        uint256 aliceBalanceBefore = pool.balanceOf(userAlice);
        uint256 bobBalanceBefore = pool.balanceOf(userBob);

        assertTrue(pool.transferFrom(userAlice, userBob, amount));

        assertEq(pool.balanceOf(userAlice), aliceBalanceBefore - amount);
        assertEq(pool.balanceOf(userBob), bobBalanceBefore + amount);
    }

    function test_TransferFrom_WithoutApproval_Reverts() public {
        uint256 amount = 10 ** pool.decimals();

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, amount)
        );
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transferFrom(userAlice, userBob, amount);
    }

    function test_TransferFrom_ExceedsApproval_Reverts() public {
        uint256 approvedAmount = 1 * 10 ** pool.decimals();
        uint256 transferAmount = 2 * 10 ** pool.decimals();

        vm.prank(userAlice);
        pool.approve(address(this), approvedAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), approvedAmount, transferAmount
            )
        );
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transferFrom(userAlice, userBob, transferAmount);
    }

    function test_TransferFrom_UpdatesAllowance() public {
        uint256 approvedAmount = 5 * 10 ** pool.decimals();
        uint256 transferAmount = 2 * 10 ** pool.decimals();

        vm.prank(userAlice);
        pool.approve(address(this), approvedAmount);

        assertTrue(pool.transferFrom(userAlice, userBob, transferAmount));

        assertEq(pool.allowance(userAlice, address(this)), approvedAmount - transferAmount);
    }

    // Bad debt blocking

    function test_Transfer_BlockedByBadDebt() public {
        // Create bad debt
        dashboard.mock_increaseLiability(steth.getSharesByPooledEth(pool.totalAssets()) + 1);

        vm.prank(userAlice);
        vm.expectRevert(abi.encodeWithSelector(StvPool.VaultInBadDebt.selector));
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transfer(userBob, 1);
    }
}
