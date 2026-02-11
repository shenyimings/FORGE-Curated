// SPDX-License-Identifier: Apache-2.0 OR MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {console} from "forge-std/console.sol";
import {Errors} from "../src/Errors.sol";

contract OperatorApprovalTest is Test, BaseTestHelper {
    MockERC20 secondToken;
    PaymentsTestHelpers helper;
    Payments payments;

    uint256 constant DEPOSIT_AMOUNT = 1000 ether;
    uint256 constant RATE_ALLOWANCE = 100 ether;
    uint256 constant LOCKUP_ALLOWANCE = 1000 ether;
    uint256 constant MAX_LOCKUP_PERIOD = 100;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();

        // Deposit funds for client
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
    }

    function testNativeFIL() public {
        vm.startPrank(USER1);
        payments.setOperatorApproval(address(0), OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);
        vm.stopPrank();
    }

    function testInvalidAddresses() public {
        // Test zero operator address
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddressNotAllowed.selector, "operator"));
        payments.setOperatorApproval(
            address(0x1), address(0), true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();
    }

    function testModifyingAllowances() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Increase allowances
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE * 2, LOCKUP_ALLOWANCE * 2, MAX_LOCKUP_PERIOD);

        // Decrease allowances
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE / 2, LOCKUP_ALLOWANCE / 2, MAX_LOCKUP_PERIOD);
    }

    function testRevokingAndReapprovingOperator() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Revoke approval
        helper.revokeOperatorApprovalAndVerify(USER1, OPERATOR);

        // Reapprove operator
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);
    }

    function testRateTrackingWithMultipleRails() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Create a rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Verify no allowance consumed yet
        helper.verifyOperatorAllowances(
            USER1, OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, 0, 0, MAX_LOCKUP_PERIOD
        );

        // 1. Set initial payment rate
        uint256 initialRate = 10 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, initialRate, 0);
        vm.stopPrank();

        // Verify rate usage matches initial rate
        helper.verifyOperatorAllowances(
            USER1, OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, initialRate, 0, MAX_LOCKUP_PERIOD
        );

        // 2. Increase payment rate
        uint256 increasedRate = 15 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, increasedRate, 0);
        vm.stopPrank();

        // Verify rate usage increased
        helper.verifyOperatorAllowances(
            USER1, OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, increasedRate, 0, MAX_LOCKUP_PERIOD
        );

        // 3. Decrease payment rate
        uint256 decreasedRate = 5 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, decreasedRate, 0);
        vm.stopPrank();

        // Verify rate usage decreased
        helper.verifyOperatorAllowances(
            USER1, OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, decreasedRate, 0, MAX_LOCKUP_PERIOD
        );

        // 4. Create second rail and set rate
        uint256 railId2 = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        uint256 rate2 = 15 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId2, rate2, 0);
        vm.stopPrank();

        // Verify combined rate usage
        helper.verifyOperatorAllowances(
            USER1, OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, decreasedRate + rate2, 0, MAX_LOCKUP_PERIOD
        );
    }

    function testRateLimitEnforcement() public {
        // Setup initial approval with limited rate allowance
        uint256 limitedRateAllowance = 10 ether;
        helper.setupOperatorApproval(USER1, OPERATOR, limitedRateAllowance, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Create rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set rate to exactly the limit
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, limitedRateAllowance, 0);
        vm.stopPrank();

        // Now try to exceed the limit - should revert
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OperatorRateAllowanceExceeded.selector, limitedRateAllowance, limitedRateAllowance + 1 ether
            )
        );
        payments.modifyRailPayment(railId, limitedRateAllowance + 1 ether, 0);
        vm.stopPrank();
    }

    // SECTION: Lockup Allowance Tracking

    function testLockupTracking() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Create rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set payment rate
        uint256 paymentRate = 10 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        vm.stopPrank();

        // 1. Set initial lockup
        uint256 lockupPeriod = 5; // 5 blocks
        uint256 initialFixedLockup = 100 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId, lockupPeriod, initialFixedLockup);
        vm.stopPrank();

        // Calculate expected lockup usage
        uint256 expectedLockupUsage = initialFixedLockup + (paymentRate * lockupPeriod);

        // Verify lockup usage
        helper.verifyOperatorAllowances(
            USER1, OPERATOR, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, paymentRate, expectedLockupUsage, MAX_LOCKUP_PERIOD
        );

        // 2. Increase fixed lockup
        uint256 increasedFixedLockup = 200 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId, lockupPeriod, increasedFixedLockup);
        vm.stopPrank();

        // Calculate updated expected lockup usage
        uint256 updatedExpectedLockupUsage = increasedFixedLockup + (paymentRate * lockupPeriod);

        // Verify increased lockup usage
        helper.verifyOperatorAllowances(
            USER1,
            OPERATOR,
            true,
            RATE_ALLOWANCE,
            LOCKUP_ALLOWANCE,
            paymentRate,
            updatedExpectedLockupUsage,
            MAX_LOCKUP_PERIOD
        );

        // 3. Decrease fixed lockup
        uint256 decreasedFixedLockup = 50 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId, lockupPeriod, decreasedFixedLockup);
        vm.stopPrank();

        // Calculate reduced expected lockup usage
        uint256 finalExpectedLockupUsage = decreasedFixedLockup + (paymentRate * lockupPeriod);

        // Verify decreased lockup usage
        helper.verifyOperatorAllowances(
            USER1,
            OPERATOR,
            true,
            RATE_ALLOWANCE,
            LOCKUP_ALLOWANCE,
            paymentRate,
            finalExpectedLockupUsage,
            MAX_LOCKUP_PERIOD
        );
    }

    function testLockupLimitEnforcement() public {
        // Setup initial approval with limited lockup allowance
        uint256 limitedLockupAllowance = 100 ether;
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, limitedLockupAllowance, MAX_LOCKUP_PERIOD);

        // Create rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set payment rate
        uint256 paymentRate = 10 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        vm.stopPrank();

        // Try to set fixed lockup that exceeds allowance
        uint256 excessiveLockup = 110 ether;
        (,,,, uint256 currentLockupUsage,) = payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        uint256 attemptedUsage = currentLockupUsage + excessiveLockup;
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OperatorLockupAllowanceExceeded.selector, limitedLockupAllowance, attemptedUsage
            )
        );
        payments.modifyRailLockup(railId, 0, excessiveLockup);
        vm.stopPrank();
    }

    function testAllowanceEdgeCases() public {
        // 1. Test exact allowance consumption
        uint256 exactRateAllowance = 10 ether;
        uint256 exactLockupAllowance = 100 ether;
        helper.setupOperatorApproval(USER1, OPERATOR, exactRateAllowance, exactLockupAllowance, MAX_LOCKUP_PERIOD);

        // Create rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Use exactly the available rate allowance
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, exactRateAllowance, 0);
        vm.stopPrank();

        // Use exactly the available lockup allowance
        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId, 0, exactLockupAllowance);
        vm.stopPrank();

        // Verify allowances are fully consumed
        helper.verifyOperatorAllowances(
            USER1,
            OPERATOR,
            true,
            exactRateAllowance,
            exactLockupAllowance,
            exactRateAllowance,
            exactLockupAllowance,
            MAX_LOCKUP_PERIOD
        );

        // 2. Test zero allowance behavior
        helper.setupOperatorApproval(USER1, OPERATOR, 0, 0, MAX_LOCKUP_PERIOD);

        // Create rail with zero allowances
        uint256 railId2 = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Attempt to set non-zero rate (should fail)
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OperatorRateAllowanceExceeded.selector, 0, exactRateAllowance + 1)
        );
        payments.modifyRailPayment(railId2, 1, 0);
        vm.stopPrank();

        // Attempt to set non-zero lockup (should fail)
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OperatorLockupAllowanceExceeded.selector, 0, exactLockupAllowance + 1)
        );
        payments.modifyRailLockup(railId2, 0, 1);
        vm.stopPrank();
    }

    function testOperatorAuthorizationBoundaries() public {
        // 1. Test unapproved operator
        // Try to create a rail and expect it to fail
        helper.expectcreateRailToRevertWithoutOperatorApproval();

        // 2. Setup approval and create rail
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // 3. Test non-operator rail modification
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailOperatorAllowed.selector, OPERATOR, USER1));
        payments.modifyRailPayment(railId, 10 ether, 0);
        vm.stopPrank();

        // 4. Revoke approval and verify operator can't create new rails
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()), OPERATOR, false, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Verify operator approval was revoked
        // Try to create a rail and expect it to fail
        helper.expectcreateRailToRevertWithoutOperatorApproval();

        // 5. Verify operator can still modify existing rails after approval revocation
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 5 ether, 0);
        vm.stopPrank();

        // 6. Test client authorization (operator can't set approvals for client)
        vm.startPrank(OPERATOR);
        payments.setOperatorApproval(
            address(helper.testToken()), USER2, true, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Verify operator approval was not set for client
        (bool isApproved,,,,,) = payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertFalse(isApproved, "Second operator should not be approved for client");
    }

    function testOneTimePaymentScenarios() public {
        // Setup approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Create rail with fixed lockup
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        uint256 paymentRate = 10 ether;
        uint256 fixedLockup = 100 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        payments.modifyRailLockup(railId, 0, fixedLockup);
        vm.stopPrank();

        uint256 oneTimeAmount = 30 ether;
        helper.executeOneTimePayment(railId, OPERATOR, oneTimeAmount);

        // 2. Test complete fixed lockup consumption using one time payment
        uint256 remainingFixedLockup = fixedLockup - oneTimeAmount;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, remainingFixedLockup);
        vm.stopPrank();

        // Verify fixed lockup is now zero
        Payments.RailView memory rail = payments.getRail(railId);
        assertEq(rail.lockupFixed, 0, "Fixed lockup should be zero");

        // 3. Test excessive payment reverts
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OneTimePaymentExceedsLockup.selector, railId, rail.lockupFixed, 1)
        );
        payments.modifyRailPayment(railId, paymentRate, 1); // Lockup is now 0, so any payment should fail
        vm.stopPrank();
    }

    function testAllowanceChangesWithOneTimePayments() public {
        // Setup approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, 1000 ether, MAX_LOCKUP_PERIOD);

        // Create rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        uint256 paymentRate = 10 ether;
        uint256 fixedLockup = 800 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        payments.modifyRailLockup(railId, 0, fixedLockup);
        vm.stopPrank();

        // 1. Test allowance reduction after fixed lockup set
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()),
            OPERATOR,
            true,
            RATE_ALLOWANCE,
            500 ether, // below fixed lockup of 800 ether,
            MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should still be able to make one-time payments up to the fixed lockup
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 300 ether);
        vm.stopPrank();

        // Check that one-time payment succeeded despite reduced allowance
        Payments.RailView memory rail = payments.getRail(railId);
        assertEq(rail.lockupFixed, fixedLockup - 300 ether, "Fixed lockup not reduced correctly");

        // 2. Test zero allowance after fixed lockup set
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()),
            OPERATOR,
            true,
            RATE_ALLOWANCE,
            0, // zero allowance
            MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should still be able to make one-time payments up to the fixed lockup
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 200 ether);
        vm.stopPrank();

        // Check that one-time payment succeeded despite zero allowance
        rail = payments.getRail(railId);
        assertEq(rail.lockupFixed, 300 ether, "Fixed lockup not reduced correctly");
    }

    function test_OperatorCanReduceUsageOfExistingRailDespiteInsufficientAllowance() public {
        // Client allows operator to use up to 90 rate/30 lockup
        helper.setupOperatorApproval(USER1, OPERATOR, 90 ether, 30 ether, MAX_LOCKUP_PERIOD);

        // Operator creates a rail using 50 rate/20 lockup
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 50 ether, 0);
        payments.modifyRailLockup(railId, 0, 20 ether);
        vm.stopPrank();

        // Client reduces allowance to below what's already being used
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()),
            OPERATOR,
            true,
            40 ether, // below current usage of 50 ether
            15 ether, // below current usage of 20 ether
            MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should still be able to reduce usage of rate/lockup on existing rail
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 30 ether, 0);
        payments.modifyRailLockup(railId, 0, 10 ether);
        vm.stopPrank();

        // Allowance - usage should be 40 - 30 = 10 for rate, 15 - 10 = 5 for lockup
        (
            ,
            /*bool isApproved*/
            uint256 rateAllowance,
            uint256 lockupAllowance,
            uint256 rateUsage,
            uint256 lockupUsage,
        ) = helper.payments().operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertEq(rateAllowance - rateUsage, 10 ether);
        assertEq(lockupAllowance - lockupUsage, 5 ether);

        // Even though the operator can reduce usage on existing rails despite insufficient allowance,
        // they should not be able to create new rail configurations with non-zero rate/lockup

        // Create a new rail, which should succeed
        uint256 railId2 = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        uint256 attemptedUsage = rateUsage + 11 ether;

        // But attempting to set non-zero rate on the new rail should fail due to insufficient allowance
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OperatorRateAllowanceExceeded.selector, rateAllowance, attemptedUsage)
        );
        payments.modifyRailPayment(railId2, 11 ether, 0);
        vm.stopPrank();

        (,,,, lockupUsage,) = payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        uint256 oldLockupFixed = payments.getRail(railId2).lockupFixed;
        uint256 newLockupFixed = 6 ether;
        uint256 lockupIncrease = 0;
        if (newLockupFixed > oldLockupFixed) {
            lockupIncrease = newLockupFixed - oldLockupFixed;
        }
        attemptedUsage = lockupUsage + lockupIncrease;

        // Similarly, attempting to set non-zero lockup on the new rail should fail
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OperatorLockupAllowanceExceeded.selector, lockupAllowance, attemptedUsage)
        );
        payments.modifyRailLockup(railId2, 0, 6 ether);
        vm.stopPrank();
    }

    function testAllowanceReductionScenarios() public {
        // 1. Test reducing rate allowance below current usage
        // Setup approval
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            100 ether, // 100 ether rate allowance
            1000 ether,
            MAX_LOCKUP_PERIOD
        );

        // Create rail and set rate
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 50 ether, 0);
        vm.stopPrank();

        // Client reduces rate allowance below current usage
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()),
            OPERATOR,
            true,
            30 ether, // below current usage of 50 ether
            1000 ether,
            MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should be able to decrease rate
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 30 ether, 0); // Decrease to allowance
        vm.stopPrank();

        (
            , // isApproved
            uint256 rateAllowance,
            ,
            ,
            ,
        ) = payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        uint256 attemptedRateUsage = 40 ether;
        // Operator should not be able to increase rate above current allowance
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OperatorRateAllowanceExceeded.selector, rateAllowance, attemptedRateUsage)
        );
        payments.modifyRailPayment(railId, attemptedRateUsage, 0); // Try to increase above allowance
        vm.stopPrank();

        // 2. Test zeroing rate allowance after usage
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()),
            OPERATOR,
            true,
            0, // zero allowance
            1000 ether,
            MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should be able to decrease rate
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 20 ether, 0);
        vm.stopPrank();

        // Operator should not be able to increase rate at all
        vm.startPrank(OPERATOR);
        // Payments.OperatorApproval approval = payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(Errors.OperatorRateAllowanceExceeded.selector, 0, 21 ether));
        payments.modifyRailPayment(railId, 21 ether, 0);
        vm.stopPrank();

        // 3. Test reducing lockup allowance below current usage
        // Create a new rail for lockup testing
        uint256 railId2 = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Reset approval with high lockup
        helper.setupOperatorApproval(USER1, OPERATOR, 50 ether, 1000 ether, MAX_LOCKUP_PERIOD);

        // Set fixed lockup
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId2, 10 ether, 0);
        payments.modifyRailLockup(railId2, 0, 500 ether);
        vm.stopPrank();

        // Client reduces lockup allowance below current usage
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()),
            OPERATOR,
            true,
            50 ether,
            300 ether, // below current usage of 500 ether
            MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should be able to decrease fixed lockup
        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId2, 0, 200 ether);
        vm.stopPrank();

        // Operator should not be able to increase fixed lockup above current allowance
        vm.startPrank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(Errors.OperatorLockupAllowanceExceeded.selector, 300 ether, 400 ether));
        payments.modifyRailLockup(railId2, 0, 400 ether);
        vm.stopPrank();
    }

    function testComprehensiveApprovalLifecycle() public {
        // This test combines multiple approval lifecycle aspects into one comprehensive test

        // Setup approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Create two rails with different parameters
        uint256 railId1 = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        uint256 railId2 = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set parameters for first rail
        uint256 rate1 = 10 ether;
        uint256 lockupPeriod1 = 5;
        uint256 fixedLockup1 = 50 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId1, rate1, 0);
        payments.modifyRailLockup(railId1, lockupPeriod1, fixedLockup1);
        vm.stopPrank();

        // Set parameters for second rail
        uint256 rate2 = 15 ether;
        uint256 lockupPeriod2 = 3;
        uint256 fixedLockup2 = 30 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId2, rate2, 0);
        payments.modifyRailLockup(railId2, lockupPeriod2, fixedLockup2);
        vm.stopPrank();

        // Calculate expected usage
        uint256 expectedRateUsage = rate1 + rate2;
        uint256 expectedLockupUsage = fixedLockup1 + (rate1 * lockupPeriod1) + fixedLockup2 + (rate2 * lockupPeriod2);

        // Verify combined usage
        helper.verifyOperatorAllowances(
            USER1,
            OPERATOR,
            true,
            RATE_ALLOWANCE,
            LOCKUP_ALLOWANCE,
            expectedRateUsage,
            expectedLockupUsage,
            MAX_LOCKUP_PERIOD
        );

        // Make one-time payment for first rail
        uint256 oneTimeAmount = 20 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId1, rate1, oneTimeAmount);
        vm.stopPrank();

        // Revoke approval
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()), OPERATOR, false, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should still be able to modify existing rails
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId1, rate1 - 2 ether, 0);
        payments.modifyRailLockup(railId2, lockupPeriod2, fixedLockup2 - 10 ether);
        vm.stopPrank();

        // Testing that operator shouldn't be able to create a new rail using try/catch
        helper.expectcreateRailToRevertWithoutOperatorApproval();

        // Reapprove with reduced allowances
        vm.startPrank(USER1);
        payments.setOperatorApproval(
            address(helper.testToken()),
            OPERATOR,
            true,
            20 ether, // Only enough for current rails
            100 ether,
            MAX_LOCKUP_PERIOD
        );
        vm.stopPrank();

        // Operator should be able to create a new rail
        uint256 railId3 = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // But should not be able to exceed the new allowance
        vm.startPrank(OPERATOR);
        (, uint256 rateAllowance,, uint256 rateUsage,,) =
            payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        uint256 attempted = rateUsage + 10 ether; // Attempt to set rate above allowance
        vm.expectRevert(abi.encodeWithSelector(Errors.OperatorRateAllowanceExceeded.selector, rateAllowance, attempted));
        payments.modifyRailPayment(railId3, 10 ether, 0); // Would exceed new rate allowance
        vm.stopPrank();
    }

    function testMaxLockupPeriodEnforcement() public {
        // Setup initial approval with limited lockup period
        uint256 limitedMaxLockupPeriod = 5; // 5 blocks max lockup period
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, limitedMaxLockupPeriod);

        // Create rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set payment rate
        uint256 paymentRate = 10 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        vm.stopPrank();

        // Set lockup period exactly at the limit
        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId, limitedMaxLockupPeriod, 50 ether);
        vm.stopPrank();

        // Now try to exceed the max lockup period - should revert
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LockupPeriodExceedsOperatorMaximum.selector,
                address(helper.testToken()),
                OPERATOR,
                limitedMaxLockupPeriod,
                limitedMaxLockupPeriod + 1
            )
        );
        payments.modifyRailLockup(railId, limitedMaxLockupPeriod + 1, 50 ether);
        vm.stopPrank();
    }

    // Verify that operators can reduce lockup period even if it's over the max
    function testReducingLockupPeriodBelowMax() public {
        // Setup initial approval with high max lockup period
        uint256 initialMaxLockupPeriod = 20; // 20 blocks initially
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, initialMaxLockupPeriod);
        // Create rail
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);
        // Set payment rate and high lockup period
        uint256 paymentRate = 10 ether;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        payments.modifyRailLockup(railId, 15, 50 ether); // 15 blocks period
        vm.stopPrank();

        // Now client reduces max lockup period
        vm.startPrank(USER1);
        uint256 finalMaxLockupPeriod = 5; // Reduce to 5 blocks
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, finalMaxLockupPeriod);
        vm.stopPrank();

        // Operator should be able to reduce period below the new max
        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId, 4, 50 ether); // Lower to 4 blocks
        vm.stopPrank();

        // But not increase it above the new max, even though it's lower than what it was
        vm.startPrank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LockupPeriodExceedsOperatorMaximum.selector,
                address(helper.testToken()),
                OPERATOR,
                finalMaxLockupPeriod,
                6
            )
        );
        payments.modifyRailLockup(railId, 6, 50 ether); // Try to increase to 6 blocks, which is over the new max of 5
        vm.stopPrank();
    }

    // SECTION: Increase Operator Approval Tests

    function testIncreaseOperatorApproval_HappyPath() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Verify initial state
        (bool isApproved, uint256 rateAllowance, uint256 lockupAllowance,,, uint256 maxLockupPeriod) =
            payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertEq(isApproved, true);
        assertEq(rateAllowance, RATE_ALLOWANCE);
        assertEq(lockupAllowance, LOCKUP_ALLOWANCE);
        assertEq(maxLockupPeriod, MAX_LOCKUP_PERIOD);

        // Increase allowances
        uint256 rateIncrease = 50 ether;
        uint256 lockupIncrease = 500 ether;

        vm.startPrank(USER1);
        payments.increaseOperatorApproval(address(helper.testToken()), OPERATOR, rateIncrease, lockupIncrease);
        vm.stopPrank();

        // Verify increased allowances
        (isApproved, rateAllowance, lockupAllowance,,, maxLockupPeriod) =
            payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertEq(isApproved, true);
        assertEq(rateAllowance, RATE_ALLOWANCE + rateIncrease);
        assertEq(lockupAllowance, LOCKUP_ALLOWANCE + lockupIncrease);
        assertEq(maxLockupPeriod, MAX_LOCKUP_PERIOD); // Should remain unchanged
    }

    function testIncreaseOperatorApproval_ZeroIncrease() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Increase by zero (should work but not change anything)
        vm.startPrank(USER1);
        payments.increaseOperatorApproval(address(helper.testToken()), OPERATOR, 0, 0);
        vm.stopPrank();

        // Verify allowances remain the same
        (bool isApproved, uint256 rateAllowance, uint256 lockupAllowance,,, uint256 maxLockupPeriod) =
            payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertEq(isApproved, true);
        assertEq(rateAllowance, RATE_ALLOWANCE);
        assertEq(lockupAllowance, LOCKUP_ALLOWANCE);
        assertEq(maxLockupPeriod, MAX_LOCKUP_PERIOD);
    }

    function testIncreaseOperatorApproval_OperatorNotApproved() public {
        // Get token address before setting up expectRevert
        address tokenAddress = address(helper.testToken());

        // Try to increase approval for non-approved operator
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(Errors.OperatorNotApproved.selector, USER1, OPERATOR));
        payments.increaseOperatorApproval(tokenAddress, OPERATOR, 50 ether, 500 ether);
        vm.stopPrank();
    }

    function testIncreaseOperatorApproval_ZeroOperatorAddress() public {
        // Get token address before setting up expectRevert
        address tokenAddress = address(helper.testToken());

        // Try to increase approval for zero address operator
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddressNotAllowed.selector, "operator"));
        payments.increaseOperatorApproval(tokenAddress, address(0), 50 ether, 500 ether);
        vm.stopPrank();
    }

    function testIncreaseOperatorApproval_AfterRevocation() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Revoke approval
        helper.revokeOperatorApprovalAndVerify(USER1, OPERATOR);

        // Get token address before setting up expectRevert
        address tokenAddress = address(helper.testToken());

        // Try to increase revoked approval
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(Errors.OperatorNotApproved.selector, USER1, OPERATOR));
        payments.increaseOperatorApproval(tokenAddress, OPERATOR, 50 ether, 500 ether);
        vm.stopPrank();
    }

    function testIncreaseOperatorApproval_WithExistingUsage() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // Create rail and use some allowance
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);
        uint256 paymentRate = 30 ether;
        uint256 lockupFixed = 200 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        payments.modifyRailLockup(railId, 0, lockupFixed);
        vm.stopPrank();

        // Verify usage before increase
        (, uint256 rateAllowanceBefore, uint256 lockupAllowanceBefore, uint256 rateUsage, uint256 lockupUsage,) =
            payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertEq(rateUsage, paymentRate);
        assertEq(lockupUsage, lockupFixed);

        // Increase allowances
        uint256 rateIncrease = 70 ether;
        uint256 lockupIncrease = 800 ether;

        vm.startPrank(USER1);
        payments.increaseOperatorApproval(address(helper.testToken()), OPERATOR, rateIncrease, lockupIncrease);
        vm.stopPrank();

        // Verify allowances increased but usage remains the same
        (, uint256 rateAllowanceAfter, uint256 lockupAllowanceAfter, uint256 rateUsageAfter, uint256 lockupUsageAfter,)
        = payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertEq(rateAllowanceAfter, rateAllowanceBefore + rateIncrease);
        assertEq(lockupAllowanceAfter, lockupAllowanceBefore + lockupIncrease);
        assertEq(rateUsageAfter, rateUsage); // Usage should remain unchanged
        assertEq(lockupUsageAfter, lockupUsage); // Usage should remain unchanged
    }

    function testIncreaseOperatorApproval_MultipleIncreases() public {
        // Setup initial approval
        helper.setupOperatorApproval(USER1, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD);

        // First increase
        uint256 firstRateIncrease = 25 ether;
        uint256 firstLockupIncrease = 250 ether;

        vm.startPrank(USER1);
        payments.increaseOperatorApproval(address(helper.testToken()), OPERATOR, firstRateIncrease, firstLockupIncrease);
        vm.stopPrank();

        // Second increase
        uint256 secondRateIncrease = 35 ether;
        uint256 secondLockupIncrease = 350 ether;

        vm.startPrank(USER1);
        payments.increaseOperatorApproval(
            address(helper.testToken()), OPERATOR, secondRateIncrease, secondLockupIncrease
        );
        vm.stopPrank();

        // Verify cumulative increases
        (, uint256 rateAllowance, uint256 lockupAllowance,,,) =
            payments.operatorApprovals(address(helper.testToken()), USER1, OPERATOR);
        assertEq(rateAllowance, RATE_ALLOWANCE + firstRateIncrease + secondRateIncrease);
        assertEq(lockupAllowance, LOCKUP_ALLOWANCE + firstLockupIncrease + secondLockupIncrease);
    }
}
