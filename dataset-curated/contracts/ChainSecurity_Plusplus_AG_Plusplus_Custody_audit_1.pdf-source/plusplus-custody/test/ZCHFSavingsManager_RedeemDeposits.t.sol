// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZCHFSavingsManagerTestBase} from "./helpers/ZCHFSavingsManagerTestBase.sol";
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";
import {IZCHFErrors} from "./interfaces/IZCHFErrors.sol";
import {RedemptionLimiter} from "src/RedemptionLimiter.sol";

/// @title ZCHFSavingsManager_RedeemDeposits
/// @notice Unit tests for the redeemDeposits() function. These tests
/// validate access control, error conditions and correct computation of
/// principal plus interest when withdrawing deposits.
contract ZCHFSavingsManager_RedeemDeposits is ZCHFSavingsManagerTestBase {
    // Declare events for expectEmit
    event DepositCreated(bytes32 indexed identifier, uint192 amount);
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);

    /// @notice Only the operator should be able to call redeemDeposits().
    function testRevertRedeemWhenCallerNotOperator() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(1));
        vm.prank(user);
        vm.expectRevert();
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Receiver must hold the RECEIVER_ROLE or the call should revert.
    function testRevertRedeemWhenReceiverInvalid() public {
        // create a valid deposit first
        depositExample(bytes32(uint256(1)), 100, user);
        // use an address without the role
        address invalidReceiver = makeAddr("invalidReceiver");
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(1));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.InvalidReceiver.selector, invalidReceiver));
        manager.redeemDeposits(ids, invalidReceiver);
    }

    /// @notice Redeeming a non-existing deposit should revert.
    function testRevertRedeemWhenDepositNotFound() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(999));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.DepositNotFound.selector, ids[0]));
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Redeeming a single deposit should withdraw principal plus net interest,
    /// emit an event and clear the deposit.
    function testRedeemSingleDeposit() public {
        // Set up a large deposit to ensure positive interest accrues. Using
        // 1e20 units keeps calculations within the uint192 range while
        // generating non-zero interest.
        uint192 amount = 1e20;
        bytes32 id = bytes32(uint256(123));
        uint40 createdAt = uint40(block.timestamp);

        // Create the deposit
        vm.warp(block.timestamp);
        depositExample(id, amount, user);

        // Retrieve the stored deposit to access ticksAtDeposit
        (uint192 storedInitial, uint40 storedCreatedAt, uint64 storedTicksAtDeposit) = manager.deposits(id);
        assertEq(storedInitial, amount);
        assertEq(storedCreatedAt, createdAt);

        // Simulate a large number of tick increments so that totalInterest > 0.
        // Choose deltaTicks = 1e10.
        uint64 deltaTicks = 10_000_000_000;
        savings.setTick(storedTicksAtDeposit + deltaTicks);

        // Advance time by 30 days to accumulate some fee exposure.
        uint256 duration = 30 days;
        vm.warp(block.timestamp + duration);

        // Compute expected values using the contract's formula
        uint256 totalInterest = uint256(deltaTicks) * amount / 1_000_000 / 365 days;
        uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee = feeTicks * amount / 1_000_000 / 365 days;
        uint256 expectedNet = totalInterest > fee ? totalInterest - fee : 0;
        uint192 expectedTotal = uint192(amount + expectedNet);

        // Expect a DepositRedeemed event
        vm.expectEmit(true, false, false, true);
        emit DepositRedeemed(id, expectedTotal);

        // Redeem the deposit
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Verify that the savings module withdrawal was correct
        assertEq(savings.lastWithdrawTarget(), receiver);
        assertEq(savings.lastWithdrawAmount(), expectedTotal);

        // Verify the deposit is cleared
        (uint192 finalPrincipal, uint192 finalInterest) = manager.getDepositDetails(id);
        assertEq(finalPrincipal, 0);
        assertEq(finalInterest, 0);
    }

    /// @notice Redeem multiple deposits in a single call and verify that the
    /// combined amount is withdrawn from the savings module.
    function testRedeemMultipleDeposits() public {
        // Create two deposits with large amounts to ensure interest accrual
        bytes32 id1 = bytes32(uint256(1));
        bytes32 id2 = bytes32(uint256(2));
        uint192 amt1 = 1e19;
        uint192 amt2 = 5e19;
        vm.warp(1); // ensure createdAt is deterministic
        depositExample(id1, amt1, user);
        depositExample(id2, amt2, user);

        // Retrieve their ticksAtDeposit
        (,, uint64 ticksAtDeposit1) = manager.deposits(id1);
        (,, uint64 ticksAtDeposit2) = manager.deposits(id2);
        // Ensure ticksAtDeposit are equal since both deposits were created at the same time
        assertEq(ticksAtDeposit1, ticksAtDeposit2);

        // Simulate 1e9 deltaTicks for both deposits
        uint64 deltaTicks = 1_000_000_000;
        savings.setTick(ticksAtDeposit1 + deltaTicks);

        // Advance time by 15 days
        uint256 duration = 15 days;
        vm.warp(block.timestamp + duration);

        // Compute expected net interest for each deposit
        uint256 totalInterest1 = uint256(deltaTicks) * amt1 / 1_000_000 / 365 days;
        uint256 totalInterest2 = uint256(deltaTicks) * amt2 / 1_000_000 / 365 days;
        uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee1 = feeTicks * amt1 / 1_000_000 / 365 days;
        uint256 fee2 = feeTicks * amt2 / 1_000_000 / 365 days;
        uint256 net1 = totalInterest1 > fee1 ? totalInterest1 - fee1 : 0;
        uint256 net2 = totalInterest2 > fee2 ? totalInterest2 - fee2 : 0;
        uint192 total1 = uint192(amt1 + net1);
        uint192 total2 = uint192(amt2 + net2);
        uint192 expectedTotal = total1 + total2;

        // Expect events in order
        vm.expectEmit(true, false, false, true);
        emit DepositRedeemed(id1, total1);
        vm.expectEmit(true, false, false, true);
        emit DepositRedeemed(id2, total2);

        // Redeem both deposits
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Verify aggregated withdrawal
        assertEq(savings.lastWithdrawTarget(), receiver);
        assertEq(savings.lastWithdrawAmount(), expectedTotal);
        // Deposits should be gone
        (uint192 f1,) = manager.getDepositDetails(id1);
        (uint192 f2,) = manager.getDepositDetails(id2);
        assertEq(f1, 0);
        assertEq(f2, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                         Withdrawal Quota (Redeem) Tests
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Redeeming without a daily limit set for the operator reverts
    function testQuota_RevertWhen_LimitNotSetOnRedeem() public {
        // Ensure no limit was set for operator
        address operator2 = makeAddr("operator2");
        vm.prank(admin);
        manager.grantRole(OPERATOR_ROLE, operator2);

        // Create a small deposit
        bytes32 id = bytes32(uint256(1001));
        depositExample(id, 600, user);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;

        vm.prank(operator2);
        vm.expectRevert(abi.encodeWithSelector(RedemptionLimiter.LimitNotSet.selector));
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Redeeming more than available quota reverts
    function testQuota_RevertWhen_ExceedsAvailable() public {
        // Set a small limit
        vm.prank(admin);
        manager.setDailyLimit(operator, 500);

        // Create a deposit larger than the limit; redeem immediately so netInterest = 0
        bytes32 id = bytes32(uint256(1002));
        depositExample(id, 600, user);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(RedemptionLimiter.WithdrawalLimitExceeded.selector));
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Consuming quota reduces availability and refills linearly with time
    function testQuota_ConsumeAndRefillOverTime() public {
        vm.prank(admin);
        manager.setDailyLimit(operator, 1_000);

        // Create and redeem 600
        bytes32 id = bytes32(uint256(1003));
        depositExample(id, 600, user);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;

        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Immediately after redeem: available = 1_000 - 600
        assertEq(manager.availableRedemptionQuota(operator), 400);

        uint256 ts1 = block.timestamp + 12 hours;
        uint256 ts2 = block.timestamp + 24 hours;
        // After 12 hours, refill = 1_000 * 0.5 = 500, so available = min(400 + 500, 1_000) = 900
        vm.warp(ts1);
        assertEq(manager.availableRedemptionQuota(operator), 900);

        // After another 12 hours, clamped to full
        vm.warp(ts2);
        assertEq(manager.availableRedemptionQuota(operator), 1_000);
    }

    /// @notice Second redemption succeeds only after sufficient refill has accrued
    function testQuota_SecondRedemptionRequiresRefill() public {
        vm.prank(admin);
        manager.setDailyLimit(operator, 1_000);

        // First redemption of 700
        bytes32 id1 = bytes32(uint256(2001));
        depositExample(id1, 700, user);
        bytes32[] memory ids1 = new bytes32[](1);
        ids1[0] = id1;

        vm.prank(operator);
        manager.redeemDeposits(ids1, receiver);
        assertEq(manager.availableRedemptionQuota(operator), 300);

        // Create a second deposit of 600
        bytes32 id2 = bytes32(uint256(2002));
        depositExample(id2, 600, user);
        bytes32[] memory ids2 = new bytes32[](1);
        ids2[0] = id2;

        // Immediately trying to redeem should exceed available (300)
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(RedemptionLimiter.WithdrawalLimitExceeded.selector));
        manager.redeemDeposits(ids2, receiver);

        // After 12 hours, available = 300 + 500 = 800 → still less than 600? No, it's enough; redeem should now succeed.
        vm.warp(block.timestamp + 12 hours);
        vm.prank(operator);
        manager.redeemDeposits(ids2, receiver);

        // Available should now be 800 - 600 = 200
        assertEq(manager.availableRedemptionQuota(operator), 200);
    }

    /// @notice Refill rounding: tiny elapsed times should produce discrete step increases
    function testQuota_RefillRoundingSmallDeltas() public {
        vm.prank(admin);
        manager.setDailyLimit(operator, 1_000);

        // Consume 600 immediately
        bytes32 id = bytes32(uint256(3001));
        depositExample(id, 600, user);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;

        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);
        assertEq(manager.availableRedemptionQuota(operator), 400);

        // After 1 second: floor(1000 * 1 / 86400) == 0 → still 400
        vm.warp(block.timestamp + 1);
        assertEq(manager.availableRedemptionQuota(operator), 400);

        // After 87 seconds: floor(1000 * 87 / 86400) == 1 → becomes 401
        vm.warp(block.timestamp + 86); // total +87
        assertEq(manager.availableRedemptionQuota(operator), 401);
    }

    /// @notice Quotas are independent per user
    function testQuota_MultiUserIsolation() public {
        address operator2 = makeAddr("operator2");
        vm.prank(admin);
        manager.grantRole(OPERATOR_ROLE, operator2);

        vm.startPrank(admin);
        manager.setDailyLimit(operator, 1_000);
        manager.setDailyLimit(operator2, 500);
        vm.stopPrank();

        // Operator consumes 300
        bytes32 id1 = bytes32(uint256(4001));
        depositExample(id1, 300, user);
        bytes32[] memory ids1 = new bytes32[](1);
        ids1[0] = id1;
        vm.prank(operator);
        manager.redeemDeposits(ids1, receiver);

        // operator: 700 left; operator2 unchanged (full 500)
        assertEq(manager.availableRedemptionQuota(operator), 700);
        assertEq(manager.availableRedemptionQuota(operator2), 500);
    }

    /// @notice Two redemptions in the same block should not refill in between
    function testQuota_SameBlockMultipleUses_NoRefillBetween() public {
        vm.prank(admin);
        manager.setDailyLimit(operator, 1_000);

        // Create two deposits
        bytes32 idA = bytes32(uint256(5001));
        bytes32 idB = bytes32(uint256(5002));
        depositExample(idA, 400, user);
        depositExample(idB, 300, user);

        // Redeem first (400)
        bytes32[] memory idsA = new bytes32[](1);
        idsA[0] = idA;
        vm.prank(operator);
        manager.redeemDeposits(idsA, receiver);
        assertEq(manager.availableRedemptionQuota(operator), 600);

        // Redeem second in the same block (no warp)
        bytes32[] memory idsB = new bytes32[](1);
        idsB[0] = idB;
        vm.prank(operator);
        manager.redeemDeposits(idsB, receiver);

        // 600 - 300 = 300 remaining; no refill happened between calls
        assertEq(manager.availableRedemptionQuota(operator), 300);
    }
}
