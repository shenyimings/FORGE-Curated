// SPDX-License-Identifier: Apache-2.0 OR MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {console} from "forge-std/console.sol";

contract OperatorApprovalUsageLeakTest is Test, BaseTestHelper {
    PaymentsTestHelpers helper;
    Payments payments;
    address testToken;

    uint256 constant DEPOSIT_AMOUNT = 1000 ether;
    uint256 constant RATE_ALLOWANCE = 200 ether;
    uint256 constant LOCKUP_ALLOWANCE = 2000 ether;
    uint256 constant MAX_LOCKUP_PERIOD = 100;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();
        testToken = address(helper.testToken());

        // Deposit funds for client
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
    }

    function testOperatorLockupUsageLeakOnRailFinalization() public {
        // Setup operator approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Create a rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set payment rate and lockup
        uint256 paymentRate = 10 ether;
        uint256 lockupPeriod = 10; // 10 blocks
        uint256 lockupFixed = 100 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        payments.modifyRailLockup(railId, lockupPeriod, lockupFixed);
        vm.stopPrank();

        // Calculate expected lockup usage
        uint256 expectedLockupUsage = lockupFixed + (paymentRate * lockupPeriod);

        console.log("Initial lockup usage calculation:");
        console.log("  Fixed lockup:", lockupFixed);
        console.log("  Rate-based lockup:", paymentRate * lockupPeriod);
        console.log("  Total expected:", expectedLockupUsage);

        // Verify initial lockup usage is correct
        helper.verifyOperatorAllowances(
            USER1, OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, paymentRate, expectedLockupUsage, MAX_LOCKUP_PERIOD
        );

        // Terminate the rail (by client)
        vm.startPrank(USER1);
        payments.terminateRail(railId);
        vm.stopPrank();

        // Get the account's lockup settled epoch
        (,,, uint256 lockupLastSettledAt) = payments.accounts(address(testToken), USER1);

        // Calculate the rail's end epoch
        uint256 endEpoch = lockupLastSettledAt + lockupPeriod;

        console.log("\nAfter termination:");
        console.log("  Current block:", block.number);
        console.log("  Lockup last settled at:", lockupLastSettledAt);
        console.log("  Rail end epoch:", endEpoch);

        // Move time forward to after the rail's end epoch
        vm.roll(endEpoch + 1);

        console.log("\nAfter time advance:");
        console.log("  Current block:", block.number);

        // Settle the rail completely - this will trigger finalizeTerminatedRail
        vm.startPrank(USER2); // Payee can settle
        (uint256 settledAmount,,, uint256 finalEpoch,) =
            payments.settleRail{value: payments.NETWORK_FEE()}(railId, endEpoch);
        vm.stopPrank();

        console.log("\nAfter settlement:");
        console.log("  Settled amount:", settledAmount);
        console.log("  Final epoch:", finalEpoch);

        // Check operator lockup usage after finalization
        (,,, uint256 rateUsageAfter, uint256 lockupUsageAfter,) =
            payments.operatorApprovals(address(testToken), USER1, OPERATOR);

        console.log("\nFinal operator usage:");
        console.log("  Rate usage:", rateUsageAfter);
        console.log("  Lockup usage:", lockupUsageAfter);

        // Assert the correct behavior: lockup usage should be 0 after finalization
        assertEq(lockupUsageAfter, 0, "Lockup usage should be 0 after rail finalization");
        assertEq(rateUsageAfter, 0, "Rate usage should be 0 after rail finalization");
    }

    function testMultipleRailsShowCumulativeLeak() public {
        // Setup operator approval with higher allowances
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE * 5, LOCKUP_ALLOWANCE * 5, MAX_LOCKUP_PERIOD);

        uint256 totalLeakedUsage = 0;

        // Create and terminate multiple rails to show cumulative effect
        for (uint256 i = 1; i <= 3; i++) {
            console.log("\n=== Rail", i, "===");

            // Create rail
            uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

            // Set payment rate and lockup
            uint256 paymentRate = 10 ether * i;
            uint256 lockupPeriod = 5 * i;
            uint256 lockupFixed = 50 ether * i;

            vm.startPrank(OPERATOR);
            payments.modifyRailPayment(railId, paymentRate, 0);
            payments.modifyRailLockup(railId, lockupPeriod, lockupFixed);
            vm.stopPrank();

            // Terminate the rail
            vm.startPrank(USER1);
            payments.terminateRail(railId);
            vm.stopPrank();

            // Get end epoch
            (,,, uint256 lockupLastSettledAt) = payments.accounts(address(testToken), USER1);
            uint256 endEpoch = lockupLastSettledAt + lockupPeriod;

            // Move time forward
            vm.roll(endEpoch + 1);

            // Settle to trigger finalization
            vm.startPrank(USER2);
            payments.settleRail{value: payments.NETWORK_FEE()}(railId, endEpoch);
            vm.stopPrank();

            // Track leaked usage
            uint256 leakedForThisRail = paymentRate * lockupPeriod;
            totalLeakedUsage += leakedForThisRail;

            console.log("  Leaked usage from this rail:", leakedForThisRail);
        }

        // Check final operator lockup usage
        (,,,, uint256 finalLockupUsage,) = payments.operatorApprovals(address(testToken), USER1, OPERATOR);

        console.log("\n=== FINAL OPERATOR USAGE ===");
        console.log("Final operator lockup usage:", finalLockupUsage);
        console.log("Expected (correct) lockup usage: 0");

        // Assert the correct behavior: all lockup usage should be cleared after all rails are finalized
        assertEq(finalLockupUsage, 0, "All lockup usage should be cleared after finalizing all rails");
    }
}
