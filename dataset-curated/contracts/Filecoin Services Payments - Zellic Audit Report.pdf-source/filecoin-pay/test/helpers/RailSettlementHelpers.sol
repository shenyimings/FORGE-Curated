// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../../src/Payments.sol";
import {MockValidator} from "../mocks/MockValidator.sol";
import {PaymentsTestHelpers} from "./PaymentsTestHelpers.sol";
import {console} from "forge-std/console.sol";

contract RailSettlementHelpers is Test {
    PaymentsTestHelpers public baseHelper;
    Payments public payments;

    constructor() {
        baseHelper = new PaymentsTestHelpers();
    }

    function initialize(Payments _payments, PaymentsTestHelpers _baseHelper) public {
        payments = _payments;
        baseHelper = _baseHelper;
    }

    struct SettlementResult {
        uint256 totalAmount;
        uint256 netPayeeAmount;
        uint256 operatorCommission;
        uint256 settledUpto;
        string note;
    }

    function setupRailWithValidatorAndRateChangeQueue(
        address from,
        address to,
        address operator,
        address validator,
        uint256[] memory rates,
        uint256 lockupPeriod,
        uint256 lockupFixed,
        uint256 maxLokkupPeriod,
        address serviceFeeRecipient
    ) public returns (uint256) {
        require(validator != address(0), "RailSettlementHelpers: validator cannot be zero address");

        // Setup operator approval with sufficient allowances
        uint256 maxRate = 0;
        for (uint256 i = 0; i < rates.length; i++) {
            if (rates[i] > maxRate) {
                maxRate = rates[i];
            }
        }

        // Calculate total lockup needed
        uint256 totalLockupAllowance = lockupFixed + (maxRate * lockupPeriod);

        // Setup operator approval with the necessary allowances
        baseHelper.setupOperatorApproval(
            from,
            operator,
            maxRate, // Rate allowance
            totalLockupAllowance, // Lockup allowance
            maxLokkupPeriod // Max lockup period
        );

        // Create rail with parameters
        uint256 railId = baseHelper.setupRailWithParameters(
            from,
            to,
            operator,
            rates[0], // Initial rate
            lockupPeriod,
            lockupFixed,
            validator,
            serviceFeeRecipient
        );

        // Apply rate changes for the rest of the rates
        vm.startPrank(operator);
        for (uint256 i = 1; i < rates.length; i++) {
            // Each change will enqueue the previous rate
            payments.modifyRailPayment(railId, rates[i], 0);

            // Advance one block to ensure the changes are at different epochs
            baseHelper.advanceBlocks(1);
        }
        vm.stopPrank();

        return railId;
    }

    function createInDebtRail(
        address from,
        address to,
        address operator,
        uint256 paymentRate,
        uint256 lockupPeriod,
        uint256 fundAmount,
        uint256 fixedLockup,
        address serviceFeeRecipient
    ) public returns (uint256) {
        baseHelper.makeDeposit(from, from, fundAmount);

        // Create a rail with specified parameters
        uint256 railId = baseHelper.setupRailWithParameters(
            from, to, operator, paymentRate, lockupPeriod, fixedLockup, address(0), serviceFeeRecipient
        );

        // Advance blocks past the lockup period to force the rail into debt
        baseHelper.advanceBlocks(lockupPeriod + 1);

        return railId;
    }

    function deployMockValidator(MockValidator.ValidatorMode mode) public returns (MockValidator) {
        return new MockValidator(mode);
    }

    function settleRailAndVerify(uint256 railId, uint256 untilEpoch, uint256 expectedAmount, uint256 expectedUpto)
        public
        returns (SettlementResult memory result)
    {
        console.log("settleRailAndVerify");
        // Get the rail details to identify payer and payee
        Payments.RailView memory rail = payments.getRail(railId);
        address payer = rail.from;
        address payee = rail.to;

        // Get balances before settlement
        Payments.Account memory payerAccountBefore = baseHelper.getAccountData(payer);
        Payments.Account memory payeeAccountBefore = baseHelper.getAccountData(payee);

        console.log("payerFundsBefore", payerAccountBefore.funds);
        console.log("payerLockupBefore", payerAccountBefore.lockupCurrent);
        console.log("payeeFundsBefore", payeeAccountBefore.funds);
        console.log("payeeLockupBefore", payeeAccountBefore.lockupCurrent);

        uint256 settlementAmount;
        uint256 netPayeeAmount;
        uint256 operatorCommission;
        uint256 settledUpto;
        string memory note;

        uint256 networkFee = payments.NETWORK_FEE();
        vm.startPrank(payer);
        (settlementAmount, netPayeeAmount, operatorCommission, settledUpto, note) =
            payments.settleRail{value: networkFee}(railId, untilEpoch);
        vm.stopPrank();

        console.log("settlementAmount", settlementAmount);
        console.log("netPayeeAmount", netPayeeAmount);
        console.log("operatorCommission", operatorCommission);
        console.log("settledUpto", settledUpto);
        console.log("note", note);

        // Verify results
        assertEq(settlementAmount, expectedAmount, "Settlement amount doesn't match expected");
        assertEq(settledUpto, expectedUpto, "Settled upto doesn't match expected");

        // Verify payer and payee balance changes
        Payments.Account memory payerAccountAfter = baseHelper.getAccountData(payer);
        Payments.Account memory payeeAccountAfter = baseHelper.getAccountData(payee);
        console.log("payerFundsAfter", payerAccountAfter.funds);
        console.log("payeeFundsAfter", payeeAccountAfter.funds);

        assertEq(
            payerAccountBefore.funds - payerAccountAfter.funds,
            settlementAmount,
            "Payer's balance reduction doesn't match settlement amount"
        );
        assertEq(
            payeeAccountAfter.funds - payeeAccountBefore.funds,
            netPayeeAmount,
            "Payee's balance increase doesn't match net payee amount"
        );

        rail = payments.getRail(railId);
        assertEq(rail.settledUpTo, expectedUpto, "Rail settled upto incorrect");

        return SettlementResult(settlementAmount, netPayeeAmount, operatorCommission, settledUpto, note);
    }

    function terminateAndSettleRail(uint256 railId, uint256 expectedAmount, uint256 expectedUpto)
        public
        returns (SettlementResult memory result)
    {
        // Get rail details to extract client and operator addresses
        Payments.RailView memory rail = payments.getRail(railId);
        address client = rail.from;
        address operator = rail.operator;

        // Terminate the rail as operator
        vm.prank(operator);
        payments.terminateRail(railId);

        // Verify rail was properly terminated
        rail = payments.getRail(railId);
        (,,, uint256 lockupLastSettledAt) = payments.accounts(address(baseHelper.testToken()), client);
        assertTrue(rail.endEpoch > 0, "Rail should be terminated");
        assertEq(
            rail.endEpoch,
            lockupLastSettledAt + rail.lockupPeriod,
            "Rail end epoch should be account lockup last settled at + rail lockup period"
        );

        return settleRailAndVerify(railId, block.number, expectedAmount, expectedUpto);
    }

    function modifyRailSettingsAndVerify(
        Payments paymentsContract,
        uint256 railId,
        address operator,
        uint256 newRate,
        uint256 newLockupPeriod,
        uint256 newFixedLockup
    ) public {
        Payments.RailView memory railBefore = paymentsContract.getRail(railId);
        address client = railBefore.from;

        // Get operator allowance usage before modifications
        (,,, uint256 rateUsageBefore, uint256 lockupUsageBefore,) =
            paymentsContract.operatorApprovals(address(baseHelper.testToken()), client, operator);

        // Calculate current lockup total
        uint256 oldLockupTotal = railBefore.lockupFixed + (railBefore.paymentRate * railBefore.lockupPeriod);

        // Calculate new lockup total
        uint256 newLockupTotal = newFixedLockup + (newRate * newLockupPeriod);

        // Modify rail settings
        vm.startPrank(operator);

        // First modify rate if needed
        if (newRate != railBefore.paymentRate) {
            paymentsContract.modifyRailPayment(railId, newRate, 0);
        }

        // Then modify lockup parameters
        if (newLockupPeriod != railBefore.lockupPeriod || newFixedLockup != railBefore.lockupFixed) {
            paymentsContract.modifyRailLockup(railId, newLockupPeriod, newFixedLockup);
        }

        vm.stopPrank();

        // Verify changes
        Payments.RailView memory railAfter = paymentsContract.getRail(railId);

        assertEq(railAfter.paymentRate, newRate, "Rail payment rate not updated correctly");

        assertEq(railAfter.lockupPeriod, newLockupPeriod, "Rail lockup period not updated correctly");

        assertEq(railAfter.lockupFixed, newFixedLockup, "Rail fixed lockup not updated correctly");

        // Get operator allowance usage after modifications
        (,,, uint256 rateUsageAfter, uint256 lockupUsageAfter,) =
            paymentsContract.operatorApprovals(address(baseHelper.testToken()), client, operator);

        // Verify rate usage changes correctly
        if (newRate > railBefore.paymentRate) {
            // Rate increased
            assertEq(
                rateUsageAfter,
                rateUsageBefore + (newRate - railBefore.paymentRate),
                "Rate usage not increased correctly after rate increase"
            );
        } else if (newRate < railBefore.paymentRate) {
            // Rate decreased
            assertEq(
                rateUsageBefore,
                rateUsageAfter + (railBefore.paymentRate - newRate),
                "Rate usage not decreased correctly after rate decrease"
            );
        } else {
            // Rate unchanged
            assertEq(rateUsageBefore, rateUsageAfter, "Rate usage changed unexpectedly when rate was not modified");
        }

        // Verify lockup usage changes correctly
        if (newLockupTotal > oldLockupTotal) {
            // Lockup increased
            assertEq(
                lockupUsageAfter,
                lockupUsageBefore + (newLockupTotal - oldLockupTotal),
                "Lockup usage not increased correctly after lockup increase"
            );
        } else if (newLockupTotal < oldLockupTotal) {
            // Lockup decreased
            assertEq(
                lockupUsageBefore,
                lockupUsageAfter + (oldLockupTotal - newLockupTotal),
                "Lockup usage not decreased correctly after lockup decrease"
            );
        } else {
            // Lockup unchanged
            assertEq(
                lockupUsageBefore, lockupUsageAfter, "Lockup usage changed unexpectedly when lockup was not modified"
            );
        }
    }
}
