// SPDX-License-Identifier: Apache-2.0 OR MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {RailSettlementHelpers} from "./helpers/RailSettlementHelpers.sol";
import {console} from "forge-std/console.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {Errors} from "../src/Errors.sol";

contract RailSettlementTest is Test, BaseTestHelper {
    PaymentsTestHelpers helper;
    RailSettlementHelpers settlementHelper;
    Payments payments;
    MockERC20 token;

    uint256 constant DEPOSIT_AMOUNT = 200 ether;
    uint256 constant MAX_LOCKUP_PERIOD = 100;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();
        token = MockERC20(address(helper.testToken()));

        // Create settlement helper with the helper that has the initialized payment contract
        settlementHelper = new RailSettlementHelpers();
        // Initialize the settlement helper with our Payments instance
        settlementHelper.initialize(payments, helper);

        // Make deposits to test accounts for testing
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
    }

    //--------------------------------
    // 1. Basic Settlement Flow Tests
    //--------------------------------

    function testBasicSettlement() public {
        // Create a rail with a simple rate
        uint256 rate = 5 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(0), // No validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance a few blocks
        helper.advanceBlocks(5);

        // Settle for the elapsed blocks
        uint256 expectedAmount = rate * 5; // 5 blocks * 5 ether
        console.log("block.number", block.number);

        settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);
    }

    function testSettleRailInDebt() public {
        uint256 rate = 50 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            3, // lockupPeriod - total locked: 150 ether (3 * 50)
            0, // No fixed lockup
            address(0),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance 7 blocks
        helper.advanceBlocks(7);

        // With 200 ether deposit and 150 ether locked, we can only pay for 1 epoch (50 ether)
        uint256 expectedAmount = 50 ether;
        uint256 expectedEpoch = 2; // Initial epoch (1) + 1 epoch

        // First settlement
        settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, expectedEpoch);

        // Settle again - should be a no-op since we're already settled to the expected epoch
        settlementHelper.settleRailAndVerify(railId, block.number, 0, expectedEpoch);

        // Add more funds and settle again
        uint256 additionalDeposit = 300 ether;
        helper.makeDeposit(USER1, USER1, additionalDeposit);

        // Should be able to settle the remaining 6 epochs
        uint256 expectedAmount2 = rate * 6; // 6 more epochs * 50 ether

        // Third settlement
        settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount2, block.number);
    }

    function testSettleRailWithRateChange() public {
        // Set up a rail
        uint256 rate = 5 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(0), // Standard validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );
        uint256 newRate1 = 6 ether;
        uint256 newRate2 = 7 ether;

        // Set the rate to 6 ether after 7 blocks
        helper.advanceBlocks(7);

        // Increase operator allowances to allow rate modification
        // We increase rate allowance = 5 + 6 + 7 ether and add buffer for lockup
        uint256 rateAllowance = rate + newRate1 + newRate2;
        uint256 lockupAllowance = (rate + newRate1 + newRate2) * 10;
        helper.setupOperatorApproval(USER1, OPERATOR, rateAllowance, lockupAllowance, MAX_LOCKUP_PERIOD);

        // Operator increases the payment rate from 5 ETH to 6 ETH per block for epochs (9-14)
        // This creates a rate change queue
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, newRate1, 0);
        vm.stopPrank();

        // Advance 6 blocks
        helper.advanceBlocks(6);

        // Operator increases the payment rate from 6 ETH to 7 ETH per block for epochs (15-21)
        // This creates a rate change queue
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, newRate2, 0);
        vm.stopPrank();

        // Advance 6 blocks
        helper.advanceBlocks(7);

        // expectedAmount = 5 * 7 + 6 * 6 + 7 * 7 = 120 ether
        uint256 expectedAmount = rate * 7 + newRate1 * 6 + newRate2 * 7;

        // settle and verify
        settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);
    }

    //--------------------------------
    // 2. Validation Scenarios
    //--------------------------------

    function testValidationWithStandardApproval() public {
        // Deploy a standard validator that approves everything
        MockValidator validator = new MockValidator(MockValidator.ValidatorMode.STANDARD);

        // Create a rail with the validator
        uint256 rate = 5 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(validator), // Standard validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance several blocks
        helper.advanceBlocks(5);

        // Verify standard validator approves full amount
        uint256 expectedAmount = rate * 5; // 5 blocks * 5 ether

        // Settle with validation
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);

        // Verify validaton note
        assertEq(result.note, "Standard approved payment", "Validator note should match");
    }

    function testValidationWithMultipleRateChanges() public {
        // Deploy a standard validator that approves everything
        MockValidator validator = new MockValidator(MockValidator.ValidatorMode.STANDARD);

        // Setup operator approval first
        helper.setupOperatorApproval(
            USER1, // from
            OPERATOR,
            10,
            100 ether,
            MAX_LOCKUP_PERIOD // lockup period
        );

        // Create a rail with the validator
        uint256 rate = 1;
        uint256 expectedAmount = 0;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(validator), // Standard validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        vm.startPrank(OPERATOR);
        while (rate++ < 10) {
            // Advance several blocks
            payments.modifyRailPayment(railId, rate, 0);
            expectedAmount += rate * 5;
            helper.advanceBlocks(5);
        }
        vm.stopPrank();

        // Settle with validation
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);

        // Verify validator note
        assertEq(result.note, "Standard approved payment", "Validator note should match");
    }

    function testValidationWithReducedAmount() public {
        // Deploy an validator that reduces payment amounts
        MockValidator validator = new MockValidator(MockValidator.ValidatorMode.REDUCE_AMOUNT);
        validator.configure(80); // 80% of the original amount

        // Create a rail with the validator
        uint256 rate = 10 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(validator), // Reduced amount validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance several blocks
        helper.advanceBlocks(5);

        // Verify reduced amount (80% of original)
        uint256 expectedAmount = (rate * 5 * 80) / 100; // 5 blocks * 10 ether * 80%

        // Settle with validation - verify against NET payee amount
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);

        assertEq(result.netPayeeAmount, expectedAmount, "Net payee amount incorrect");
        assertEq(result.operatorCommission, 0, "Operator commission incorrect");

        // Verify validator note
        assertEq(result.note, "Validator reduced payment amount", "Validator note should match");
    }

    function testValidationWithReducedDuration() public {
        // Deploy an validator that reduces settlement duration
        MockValidator validator = new MockValidator(MockValidator.ValidatorMode.REDUCE_DURATION);
        validator.configure(60); // 60% of the original duration

        // Create a rail with the validator
        uint256 rate = 10 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(validator), // Reduced duration validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance several blocks
        uint256 advanceBlocks = 5;
        helper.advanceBlocks(advanceBlocks);

        // Calculate expected settlement duration (60% of 5 blocks)
        uint256 expectedDuration = (advanceBlocks * 60) / 100;
        uint256 expectedSettledUpto = block.number - advanceBlocks + expectedDuration;
        uint256 expectedAmount = rate * expectedDuration; // expectedDuration blocks * 10 ether

        // Settle with validation
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, expectedSettledUpto);

        // Verify validator note
        assertEq(result.note, "Validator reduced settlement duration", "Validator note should match");
    }

    function testMaliciousValidatorHandling() public {
        uint256 networkFee = payments.NETWORK_FEE();
        // Deploy a malicious validator
        MockValidator validator = new MockValidator(MockValidator.ValidatorMode.MALICIOUS);

        // Create a rail with the validator
        uint256 rate = 5 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(validator), // Malicious validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance several blocks
        helper.advanceBlocks(5);

        // Attempt settlement with malicious validator - should revert
        vm.prank(USER1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ValidatorSettledBeyondSegmentEnd.selector, railId, block.number, block.number + 10
            )
        );
        payments.settleRail{value: networkFee}(railId, block.number);

        // Set the validator to return invalid amount but valid settlement duration
        validator.setMode(MockValidator.ValidatorMode.CUSTOM_RETURN);
        uint256 proposedAmount = rate * 5; // 5 blocks * 5 ether
        uint256 invalidAmount = proposedAmount * 2; // Double the correct amount
        validator.setCustomValues(invalidAmount, block.number, "Attempting excessive payment");

        // Attempt settlement with excessive amount - should also revert
        vm.prank(USER1);
        // error ValidatorModifiedAmountExceedsMaximum(uint256 railId, uint256 maxAllowed, uint256 attempted);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ValidatorModifiedAmountExceedsMaximum.selector, railId, proposedAmount, invalidAmount
            )
        );
        payments.settleRail{value: networkFee}(railId, block.number);
    }

    //--------------------------------
    // 3. Termination and Edge Cases
    //--------------------------------

    function testRailTerminationAndSettlement() public {
        uint256 networkFee = payments.NETWORK_FEE();
        uint256 rate = 10 ether;
        uint256 lockupPeriod = 5;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            lockupPeriod, // lockupPeriod
            0, // No fixed lockup
            address(0), // No validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance several blocks
        helper.advanceBlocks(3);

        // First settlement
        uint256 expectedAmount1 = rate * 3; // 3 blocks * 10 ether
        settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount1, block.number);

        // Terminate the rail
        vm.prank(OPERATOR);
        payments.terminateRail(railId);

        // Verify rail was terminated - check endEpoch is set
        Payments.RailView memory rail = payments.getRail(railId);
        assertTrue(rail.endEpoch > 0, "Rail should be terminated");

        // Verify endEpoch calculation: should be the lockupLastSettledAt (current block) + lockupPeriod
        Payments.Account memory account = helper.getAccountData(USER1);
        assertEq(
            rail.endEpoch,
            account.lockupLastSettledAt + rail.lockupPeriod,
            "End epoch should be account lockup last settled at + lockup period"
        );

        // Advance more blocks
        helper.advanceBlocks(10);

        // Get balances before final settlement
        Payments.Account memory userBefore = helper.getAccountData(USER1);
        Payments.Account memory recipientBefore = helper.getAccountData(USER2);

        // Final settlement after termination
        vm.prank(USER1);

        (uint256 settledAmount, uint256 netPayeeAmount, uint256 totalOperatorCommission, uint256 settledUpto,) =
            payments.settleRail{value: networkFee}(railId, block.number);

        // Verify that total settled amount is equal to the sum of net payee amount and operator commission
        assertEq(settledAmount, netPayeeAmount + totalOperatorCommission, "Mismatch in settled amount breakdown");

        // Should settle up to endEpoch, which is lockupPeriod blocks after the last settlement
        uint256 expectedAmount2 = rate * lockupPeriod; // lockupPeriod = 5 blocks
        assertEq(settledAmount, expectedAmount2, "Final settlement amount incorrect");
        assertEq(settledUpto, rail.endEpoch, "Final settled up to incorrect");

        // Get balances after settlement
        Payments.Account memory userAfter = helper.getAccountData(USER1);
        Payments.Account memory recipientAfter = helper.getAccountData(USER2);

        assertEq(
            userBefore.funds - userAfter.funds, expectedAmount2, "User funds not reduced correctly in final settlement"
        );
        assertEq(
            recipientAfter.funds - recipientBefore.funds,
            netPayeeAmount,
            "Recipient funds not increased correctly in final settlement"
        );

        // Verify account lockup is cleared after full settlement
        assertEq(userAfter.lockupCurrent, 0, "Account lockup should be cleared after full rail settlement");
        assertEq(userAfter.lockupRate, 0, "Account lockup rate should be zero after full rail settlement");
    }

    function testSettleAlreadyFullySettledRail() public {
        // Create a rail with standard rate
        uint256 rate = 5 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(0), // No validator
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Settle immediately without advancing blocks - should be a no-op
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, 0, block.number);

        console.log("result.note", result.note);

        // Verify the note indicates already settled
        assertTrue(
            bytes(result.note).length > 0
                && stringsEqual(result.note, string.concat("already settled up to epoch ", vm.toString(block.number))),
            "Note should indicate already settled"
        );
    }

    function testSettleRailWithRateChangeQueueForReducedAmountValidation() public {
        // Deploy an validator that reduces the payment amount by a percentage
        uint256 factor = 80; // 80% of the original amount
        MockValidator validator = new MockValidator(MockValidator.ValidatorMode.REDUCE_AMOUNT);
        validator.configure(factor);

        // Create a rail with the validator
        uint256 rate = 5 ether;
        uint256 lockupPeriod = 10;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            lockupPeriod,
            0, // No fixed lockup
            address(validator),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Simulate 5 blocks passing (blocks 1-5)
        helper.advanceBlocks(5);

        // Increase operator allowances to allow rate modification
        // We double the rate allowance and add buffer for lockup
        (, uint256 rateAllowance, uint256 lockupAllowance,,,) = helper.getOperatorAllowanceAndUsage(USER1, OPERATOR);
        helper.setupOperatorApproval(USER1, OPERATOR, rateAllowance * 2, lockupAllowance + 10 * rate, MAX_LOCKUP_PERIOD);

        // Operator doubles the payment rate from 5 ETH to 10 ETH per block
        // This creates a rate change in the queue
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, rate * 2, 0);
        vm.stopPrank();

        // Simulate 5 blocks passing (blocks 6-10)
        helper.advanceBlocks(5);

        // Calculate expected settlement:
        // Phase 1 (blocks 1-5): 5 blocks at 5 ETH/block → 25 ETH total -> after validation (80%) -> 20 ETH total
        // Phase 2 (blocks 6-10): 5 blocks at 10 ETH/block → 50 ETH total -> after validation (80%) -> 40 ETH total
        // Total after validation (80%) -> 60 ETH total
        uint256 expectedDurationOldRate = 5; // Epochs 1-5 ( rate = 5 )
        uint256 expectedDurationNewRate = 5; // Epochs 6-10 ( rate = 10 )
        uint256 expectedAmountOldRate = (rate * expectedDurationOldRate * factor) / 100; // 20 ETH (25 * 0.8)
        uint256 expectedAmountNewRate = ((rate * 2) * expectedDurationNewRate * factor) / 100; // 40 ETH (50 * 0.8)
        uint256 expectedAmount = expectedAmountOldRate + expectedAmountNewRate; // 60 ETH total

        // settle and verify rail
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);

        console.log("result.note", result.note);
    }

    function testSettleRailWithRateChangeQueueForReducedDurationValidation() public {
        uint256 networkFee = payments.NETWORK_FEE();
        // Deploy an validator that reduces the duration by a percentage
        uint256 factor = 60; // 60% of the original duration
        MockValidator validator = new MockValidator(MockValidator.ValidatorMode.REDUCE_DURATION);
        validator.configure(factor);

        // Create a rail with the validator
        uint256 rate = 5 ether;
        uint256 lockupPeriod = 10;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            lockupPeriod,
            0, // No fixed lockup
            address(validator),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Simulate 5 blocks passing (blocks 1-5)
        helper.advanceBlocks(5);

        // Initial settlement for the first 5 blocks ( epochs 1-5 )
        // Duration reduction: 5 blocks * 60% = 3 blocks settled
        // Amount: 3 blocks * 5 ETH = 15 ETH
        // LastSettledUpto: 1 + (6 - 1) * 60% = 4
        vm.prank(USER1);
        payments.settleRail{value: networkFee}(railId, block.number);
        uint256 lastSettledUpto = 1 + ((block.number - 1) * factor) / 100; // validator only settles for 60% of the duration (block.number - lastSettledUpto = epoch 1)
        vm.stopPrank();

        // update operator allowances for rate modification
        (, uint256 rateAllowance, uint256 lockupAllowance,,,) = helper.getOperatorAllowanceAndUsage(USER1, OPERATOR);
        helper.setupOperatorApproval(USER1, OPERATOR, rateAllowance * 2, lockupAllowance + 10 * rate, MAX_LOCKUP_PERIOD);

        // Operator doubles the payment rate from 5 ETH to 10 ETH per block
        // This creates a rate change in the queue
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, rate * 2, 0);
        vm.stopPrank();

        // Simulate 5 blocks passing (blocks 6-10)
        helper.advanceBlocks(5);

        // Expected settlement calculation:
        // - Rate change was at block 5, creating a boundary
        // - Duration reduction applies only to the first rate segment (epochs 1-5)
        // - We already settled 3 blocks (1-3) in the first settlement
        // - Remaining in first segment: 2 blocks (4-5) at original rate
        // - Duration reduction: 2 blocks * 60% = 1.2 blocks (truncated to 1 block)
        // - Amount: 1 epoch * 5 ETH/epoch = 5 ETH
        // - rail.settledUpto = 4 + 1 = 5 < segmentBoundary ( 6 ) => doesn't go to next settlement segment (epochs 6-10)
        uint256 firstSegmentEndBoundary = 6; // Block where rate change occurred
        uint256 expectedDuration = ((firstSegmentEndBoundary - lastSettledUpto) * factor) / 100; // (6-3)*0.6 = 1.8 → 1 block
        uint256 expectedSettledUpto = lastSettledUpto + expectedDuration; // 4 + 1 = 5
        uint256 expectedAmount = rate * expectedDuration; // 5 ETH/epoch * 1 epoch = 5 ETH

        // settle and verify rail
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, expectedSettledUpto);

        console.log("result.note", result.note);
    }

    function testModifyRailPayment_SkipsZeroRateEnqueue() public {
        uint256 initialRate = 0;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            initialRate,
            10, // lockupPeriod
            0, // fixed lockup
            address(0), // no arbiter
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // give the operator enough allowance to change the rate
        helper.setupOperatorApproval(USER1, OPERATOR, 10 ether, 100 ether, MAX_LOCKUP_PERIOD);

        // advance a few blocks so there is “history” to mark as settled
        helper.advanceBlocks(4);
        uint256 beforeBlock = block.number;

        // change rate: 0 → 5 ether
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, 5 ether, 0);
        vm.stopPrank();

        // queue must still be empty
        assertEq(payments.getRateChangeQueueSize(railId), 0, "queue should stay empty");

        // settledUpTo must equal the block where modification occurred
        Payments.RailView memory rv = payments.getRail(railId);
        assertEq(rv.settledUpTo, beforeBlock, "settledUpTo should equal current block");
    }

    //--------------------------------
    // Helper Functions
    //--------------------------------

    // Helper to compare strings
    function stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function testSettlementWithOperatorCommission() public {
        uint256 networkFee = payments.NETWORK_FEE();
        // Setup operator approval first
        helper.setupOperatorApproval(
            USER1, // from
            OPERATOR,
            10 ether, // rate allowance
            100 ether, // lockup allowance
            MAX_LOCKUP_PERIOD // max lockup period
        );

        // Create rail with 2% operator commission (200 BPS)
        uint256 operatorCommissionBps = 200;
        uint256 railId;
        vm.startPrank(OPERATOR);
        railId = payments.createRail(
            address(token),
            USER1,
            USER2,
            address(0), // no validator
            operatorCommissionBps,
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );
        vm.stopPrank();

        // Set rail parameters using modify functions
        uint256 rate = 10 ether;
        uint256 lockupPeriod = 5;
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, rate, 0);
        payments.modifyRailLockup(railId, lockupPeriod, 0); // no fixed lockup
        vm.stopPrank();

        // Advance time
        uint256 elapsedBlocks = 5;
        helper.advanceBlocks(elapsedBlocks);

        // --- Balances Before ---
        Payments.Account memory payerBefore = helper.getAccountData(USER1);
        Payments.Account memory payeeBefore = helper.getAccountData(USER2);
        Payments.Account memory operatorBefore = helper.getAccountData(OPERATOR);
        Payments.Account memory serviceFeeRecipientBefore = helper.getAccountData(SERVICE_FEE_RECIPIENT);

        // --- Settle Rail ---
        vm.startPrank(USER1); // Any participant can settle
        (uint256 settledAmount, uint256 netPayeeAmount, uint256 operatorCommission, uint256 settledUpto,) =
            payments.settleRail{value: networkFee}(railId, block.number);
        vm.stopPrank();

        // --- Expected Calculations ---
        uint256 expectedSettledAmount = rate * elapsedBlocks;
        uint256 expectedOperatorCommission =
            (expectedSettledAmount * operatorCommissionBps) / payments.COMMISSION_MAX_BPS();
        uint256 expectedNetPayeeAmount = expectedSettledAmount - expectedOperatorCommission;

        // --- Verification ---

        // 1. Return values from settleRail
        assertEq(settledAmount, expectedSettledAmount, "Returned settledAmount incorrect");
        assertEq(netPayeeAmount, expectedNetPayeeAmount, "Returned netPayeeAmount incorrect");
        assertEq(operatorCommission, expectedOperatorCommission, "Returned operatorCommission incorrect");
        assertEq(settledUpto, block.number, "Returned settledUpto incorrect");

        // 2. Balances after settlement
        Payments.Account memory payerAfter = helper.getAccountData(USER1);
        Payments.Account memory payeeAfter = helper.getAccountData(USER2);
        Payments.Account memory operatorAfter = helper.getAccountData(OPERATOR);
        Payments.Account memory serviceFeeRecipientAfter = helper.getAccountData(SERVICE_FEE_RECIPIENT);

        assertEq(payerAfter.funds, payerBefore.funds - expectedSettledAmount, "Payer funds mismatch");
        assertEq(payeeAfter.funds, payeeBefore.funds + expectedNetPayeeAmount, "Payee funds mismatch");
        assertEq(operatorAfter.funds, operatorBefore.funds, "Operator funds mismatch");
        assertEq(
            serviceFeeRecipientAfter.funds,
            serviceFeeRecipientBefore.funds + expectedOperatorCommission,
            "Service fee recipient funds mismatch"
        );
    }

    function testSettleRailWithNonZeroZeroNonZeroRateSequence() public {
        // Setup operator approval for rate modifications
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            25 ether, // rate allowance
            200 ether, // lockup allowance
            MAX_LOCKUP_PERIOD
        );

        // Create a rail with initial rate
        uint256 initialRate = 5 ether;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            initialRate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(0), // No arbiter
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance 3 blocks at initial rate (5 ether/block)
        helper.advanceBlocks(3);

        // Change rate to zero
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, 0, 0);
        vm.stopPrank();

        // Advance 4 blocks at zero rate (no payment)
        helper.advanceBlocks(4);

        // Change rate to new non-zero rate
        uint256 finalRate = 8 ether;
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, finalRate, 0);
        vm.stopPrank();

        // Advance 5 blocks at final rate (8 ether/block)
        helper.advanceBlocks(5);

        // Calculate expected settlement:
        // Phase 1 (blocks 1-3): 3 blocks at 5 ether/block = 15 ether
        // Phase 2 (blocks 4-7): 4 blocks at 0 ether/block = 0 ether
        // Phase 3 (blocks 8-12): 5 blocks at 8 ether/block = 40 ether
        // Total expected: 15 + 0 + 40 = 55 ether
        uint256 expectedAmount = (initialRate * 3) + (0 * 4) + (finalRate * 5);

        // Settle and verify
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);

        console.log("Non-zero -> Zero -> Non-zero settlement note:", result.note);
    }

    function testSettleRailWithZeroNonZeroZeroRateSequence() public {
        // Setup operator approval for rate modifications
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            15 ether, // rate allowance
            150 ether, // lockup allowance
            MAX_LOCKUP_PERIOD
        );

        // Create a rail starting with zero rate
        uint256 initialRate = 0;
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            initialRate,
            10, // lockupPeriod
            0, // No fixed lockup
            address(0), // No arbiter
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance 2 blocks at zero rate (no payment)
        helper.advanceBlocks(2);

        // Change rate to non-zero
        uint256 middleRate = 6 ether;
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, middleRate, 0);
        vm.stopPrank();

        // Advance 4 blocks at middle rate (6 ether/block)
        helper.advanceBlocks(4);

        // Change rate back to zero
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, 0, 0);
        vm.stopPrank();

        // Advance 3 blocks at zero rate again (no payment)
        helper.advanceBlocks(3);

        // Calculate expected settlement:
        // Phase 1 (blocks 1-2): 2 blocks at 0 ether/block = 0 ether
        // Phase 2 (blocks 3-6): 4 blocks at 6 ether/block = 24 ether
        // Phase 3 (blocks 7-9): 3 blocks at 0 ether/block = 0 ether
        // Total expected: 0 + 24 + 0 = 24 ether
        uint256 expectedAmount = (0 * 2) + (middleRate * 4) + (0 * 3);

        // Settle and verify
        RailSettlementHelpers.SettlementResult memory result =
            settlementHelper.settleRailAndVerify(railId, block.number, expectedAmount, block.number);

        console.log("Zero -> Non-zero -> Zero settlement note:", result.note);
    }

    function testPartialSettleOfZeroSegment() public {
        uint256 rateOn = 1;
        uint256 rateOff = 0;
        scaffoldPartialSettleOfSegment(rateOn, rateOff);
    }

    function testPartialSettleOfNonZeroSegment() public {
        uint256 rateOn = 2;
        uint256 rateOff = 1;
        scaffoldPartialSettleOfSegment(rateOn, rateOff);
    }

    function scaffoldPartialSettleOfSegment(uint256 rateOn, uint256 rateOff) public {
        helper.setupOperatorApproval(USER1, OPERATOR, 1000 ether, 100000 ether, MAX_LOCKUP_PERIOD);

        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rateOn,
            0, // No lockup period
            0, // No fixed lockup
            address(0), // No arbiter
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        /* 
        |  rate == 1 | rate == 0 | rate == 1 |
        | 100 blocks | 100 blocks | 100 blocks |
                          X^                  Y^
                    First settle          Second settle
        */
        // Advance 100 blocks and turn rate off
        // This adds a rate == 1, untilEpoch == 100 segment to the queue
        helper.advanceBlocks(100);
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, rateOff, 0);
        vm.stopPrank();

        // Advance 100 blocks and turn rate on
        // This adds a rate == 0, untilEpoch == 200 segment to the queue
        helper.advanceBlocks(100);
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, rateOn, 0);
        vm.stopPrank();

        // Advance 100 blocks and turn rate off
        // This adds a final rate == 1, untilEpoch == 300 segment to the queue
        helper.advanceBlocks(100);
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, rateOff, 0);
        vm.stopPrank();

        // Settle partway through the second segment
        settlementHelper.settleRailAndVerify(railId, 151, 100 * rateOn + 50 * rateOff, 151);

        // Settle the whole rail, we should see another 100 tokens transferred
        settlementHelper.settleRailAndVerify(railId, 301, 50 * rateOff + 100 * rateOn, 301);
    }

    function testModifyTerminatedRailBeyondEndEpoch() public {
        uint256 networkFee = payments.NETWORK_FEE();
        // Create a rail with standard parameters including fixed lockup
        uint256 rate = 10 ether;
        uint256 lockupPeriod = 5;
        uint256 fixedLockup = 10 ether; // Add fixed lockup for one-time payment tests
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            rate,
            lockupPeriod,
            fixedLockup,
            address(0), // No validator
            SERVICE_FEE_RECIPIENT
        );

        // Advance and settle to ensure the rail is active
        helper.advanceBlocks(3);
        vm.prank(USER1);
        payments.settleRail{value: networkFee}(railId, block.number);

        // Terminate the rail
        vm.prank(OPERATOR);
        payments.terminateRail(railId);

        // Get the rail's end epoch
        Payments.RailView memory rail = payments.getRail(railId);
        uint256 endEpoch = rail.endEpoch;

        // Advance blocks to reach the end epoch
        uint256 blocksToAdvance = endEpoch - block.number;
        helper.advanceBlocks(blocksToAdvance);

        // Now we're at the end epoch - try to modify rate
        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CannotModifyTerminatedRailBeyondEndEpoch.selector, railId, endEpoch, block.number
            )
        );
        payments.modifyRailPayment(railId, 5 ether, 0);

        // Also try to make a one-time payment
        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CannotModifyTerminatedRailBeyondEndEpoch.selector, railId, endEpoch, block.number
            )
        );
        payments.modifyRailPayment(railId, rate, 1 ether);

        // Advance one more block to go beyond the end epoch
        helper.advanceBlocks(1);

        // Try to modify rate again - should still revert
        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CannotModifyTerminatedRailBeyondEndEpoch.selector, railId, endEpoch, block.number
            )
        );
        payments.modifyRailPayment(railId, 5 ether, 0);

        // Try to make both rate change and one-time payment
        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CannotModifyTerminatedRailBeyondEndEpoch.selector, railId, endEpoch, block.number
            )
        );
        payments.modifyRailPayment(railId, 5 ether, 1 ether);
    }
}
