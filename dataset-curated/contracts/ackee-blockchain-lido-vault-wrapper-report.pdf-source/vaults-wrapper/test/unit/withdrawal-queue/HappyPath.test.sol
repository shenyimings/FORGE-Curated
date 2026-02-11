// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";

contract WithdrawalQueueHappyPathTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();
    }

    function test_WithdrawalQueue_HappyPath() public {
        // Deposit ETH
        pool.depositETH{value: 10 ether}(address(this), address(0));
        uint256 initialStv = pool.balanceOf(address(this));
        assertGt(initialStv, 0);

        // Mint half of the available capacity
        uint256 mintedShares = pool.calcStethSharesToMintForStv(initialStv / 2);
        pool.mintStethShares(mintedShares);
        assertEq(pool.mintedStethSharesOf(address(this)), mintedShares);

        // Request 1: Withdrawable Stv should be half of initial deposit now
        uint256 withdrawableStv = pool.unlockedStvOf(address(this));
        assertEq(withdrawableStv, initialStv / 2);

        // Request 1: Try to request full withdrawal - should fail
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        withdrawalQueue.requestWithdrawal(address(this), initialStv, 0);

        // Request 1: Withdraw part of the position
        uint256 firstWithdrawStv = initialStv / 5;
        uint256 firstRequestId = withdrawalQueue.requestWithdrawal(address(this), firstWithdrawStv, 0);

        // Request 1: Check withdrawal status
        WithdrawalQueue.WithdrawalRequestStatus memory firstStatus = withdrawalQueue.getWithdrawalStatus(firstRequestId);
        assertEq(firstStatus.amountOfStethShares, 0);
        assertEq(firstStatus.amountOfAssets, 2 ether); // initial deposit / 5
        assertEq(firstStatus.amountOfStv, firstWithdrawStv);
        assertEq(firstStatus.owner, address(this));
        assertFalse(firstStatus.isFinalized);
        assertFalse(firstStatus.isClaimed);

        // Request 1: Finalize the request
        assertEq(pool.balanceOf(address(withdrawalQueue)), firstWithdrawStv);
        assertEq(pool.mintedStethSharesOf(address(withdrawalQueue)), 0);
        assertEq(address(withdrawalQueue).balance, 0);

        _finalizeRequests(1);

        assertEq(pool.balanceOf(address(withdrawalQueue)), 0);
        assertEq(pool.mintedStethSharesOf(address(withdrawalQueue)), 0);
        assertEq(address(withdrawalQueue).balance, 2 ether);

        // Request 1: Check finalized status
        firstStatus = withdrawalQueue.getWithdrawalStatus(firstRequestId);
        assertTrue(firstStatus.isFinalized);
        assertFalse(firstStatus.isClaimed);

        // Request 1: Claim the withdrawal
        uint256 balanceBeforeClaim = address(this).balance;
        uint256 firstClaimable = withdrawalQueue.getClaimableEther(firstRequestId);
        withdrawalQueue.claimWithdrawal(address(this), firstRequestId);
        assertEq(address(this).balance, balanceBeforeClaim + firstClaimable);

        // Request 1: Check claimed status
        firstStatus = withdrawalQueue.getWithdrawalStatus(firstRequestId);
        assertTrue(firstStatus.isFinalized);
        assertTrue(firstStatus.isClaimed);
        assertEq(withdrawalQueue.getClaimableEther(firstRequestId), 0);

        // Request 1: Check remaining balances
        uint256 remainingStv = pool.balanceOf(address(this));
        assertEq(remainingStv, initialStv - firstWithdrawStv);

        // Request 1: Debt did not change
        assertEq(mintedShares, pool.mintedStethSharesOf(address(this)));

        // Request 2: Try to withdraw without burning steth shares - should fail
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        withdrawalQueue.requestWithdrawal(address(this), remainingStv, 0);

        // Request 2: Try to burn steth but without allowance - should fail
        uint256 secondSharesToBurn = mintedShares / 3;
        uint256 secondWithdrawStv = initialStv / 5;
        vm.expectRevert("Not enough allowance");
        pool.burnStethShares(secondSharesToBurn);

        // Request 2: Approve and burn steth shares
        steth.approve(address(pool), steth.getPooledEthByShares(secondSharesToBurn));
        pool.burnStethShares(secondSharesToBurn);
        assertEq(pool.mintedStethSharesOf(address(this)), mintedShares - secondSharesToBurn);

        // Request 2: Request withdrawal
        uint256 secondRequestId = withdrawalQueue.requestWithdrawal(address(this), secondWithdrawStv, 0);

        // Request 2: Check user balances after request
        remainingStv = pool.balanceOf(address(this));
        uint256 mintedSharesRemaining = pool.mintedStethSharesOf(address(this));
        assertEq(mintedSharesRemaining, mintedShares - secondSharesToBurn);
        assertEq(remainingStv, initialStv - firstWithdrawStv - secondWithdrawStv);

        // Request 2: Check withdrawal status
        WithdrawalQueue.WithdrawalRequestStatus memory secondStatus =
            withdrawalQueue.getWithdrawalStatus(secondRequestId);
        assertEq(secondStatus.amountOfStv, secondWithdrawStv);
        assertEq(secondStatus.owner, address(this));

        // Request 3: Request another withdrawal with rebalance
        uint256 thirdWithdrawStv = remainingStv;
        uint256 thirdSharesToRebalance = mintedSharesRemaining;
        uint256 thirdRequestId =
            withdrawalQueue.requestWithdrawal(address(this), thirdWithdrawStv, thirdSharesToRebalance);

        // Request 3: Check withdrawal status
        WithdrawalQueue.WithdrawalRequestStatus memory thirdStatus = withdrawalQueue.getWithdrawalStatus(thirdRequestId);
        assertEq(thirdStatus.amountOfStv, thirdWithdrawStv);
        assertEq(thirdStatus.amountOfStethShares, thirdSharesToRebalance);
        assertEq(thirdStatus.owner, address(this));

        // Request 3: Check remaining balances
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.mintedStethSharesOf(address(this)), 0);

        // Request 2 & 3: Try to finalize both requests without waiting period - should fail
        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(2, address(0));

        // Request 2 & 3: Finalize both requests after waiting period
        assertEq(pool.balanceOf(address(withdrawalQueue)), secondWithdrawStv + thirdWithdrawStv);
        assertEq(pool.mintedStethSharesOf(address(withdrawalQueue)), thirdSharesToRebalance);
        assertEq(address(withdrawalQueue).balance, 0);

        _finalizeRequests(2);

        assertEq(pool.balanceOf(address(withdrawalQueue)), 0);
        assertEq(pool.mintedStethSharesOf(address(withdrawalQueue)), 0);
        assertEq(
            address(withdrawalQueue).balance,
            // total - first withdrawal - rebalance amount
            10 ether - 2 ether - steth.getPooledEthBySharesRoundUp(thirdSharesToRebalance)
        );

        // Request 2 & 3: Check finalized status
        secondStatus = withdrawalQueue.getWithdrawalStatus(secondRequestId);
        assertTrue(secondStatus.isFinalized);
        assertFalse(secondStatus.isClaimed);

        thirdStatus = withdrawalQueue.getWithdrawalStatus(thirdRequestId);
        assertTrue(thirdStatus.isFinalized);
        assertFalse(thirdStatus.isClaimed);

        // Request 2 & 3: Find claim hints
        uint256[] memory secondRequestIds = new uint256[](2);
        secondRequestIds[0] = secondRequestId;
        secondRequestIds[1] = thirdRequestId;

        uint256 lastCheckpointIndex = withdrawalQueue.getLastCheckpointIndex();
        uint256[] memory hints = withdrawalQueue.findCheckpointHintBatch(secondRequestIds, 2, lastCheckpointIndex);
        assertEq(lastCheckpointIndex, 2); // for two finalized operations
        assertEq(hints.length, 2);
        assertEq(hints[0], 2);
        assertEq(hints[1], 2);

        // Request 2 & 3: Claim both withdrawals
        uint256 balanceBeforeSecondClaim = address(this).balance;
        uint256 secondClaimable = withdrawalQueue.getClaimableEther(secondRequestId);
        uint256 thirdClaimable = withdrawalQueue.getClaimableEther(thirdRequestId);
        withdrawalQueue.claimWithdrawalBatch(address(this), secondRequestIds, hints);
        assertEq(address(this).balance, balanceBeforeSecondClaim + secondClaimable + thirdClaimable);

        // Request 2 & 3: Check claimed status
        secondStatus = withdrawalQueue.getWithdrawalStatus(secondRequestId);
        assertTrue(secondStatus.isFinalized);
        assertTrue(secondStatus.isClaimed);
        assertEq(withdrawalQueue.getClaimableEther(secondRequestId), 0);

        thirdStatus = withdrawalQueue.getWithdrawalStatus(thirdRequestId);
        assertTrue(thirdStatus.isFinalized);
        assertTrue(thirdStatus.isClaimed);
        assertEq(withdrawalQueue.getClaimableEther(thirdRequestId), 0);

        // Final check: Withdrawal Queue
        assertEq(withdrawalQueue.getLastRequestId(), 3);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), 3);
        assertEq(withdrawalQueue.unfinalizedRequestsNumber(), 0);

        assertEq(pool.balanceOf(address(withdrawalQueue)), 0);
        assertEq(pool.mintedStethSharesOf(address(withdrawalQueue)), 0);
        assertEq(address(withdrawalQueue).balance, 0);

        // Final check: User balances
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.mintedStethSharesOf(address(this)), 0);
    }

    // Receive ETH for claiming tests
    receive() external payable {}
}
