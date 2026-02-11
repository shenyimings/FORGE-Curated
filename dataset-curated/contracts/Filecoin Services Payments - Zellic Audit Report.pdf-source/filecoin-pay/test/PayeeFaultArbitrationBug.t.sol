// SPDX-License-Identifier: Apache-2.0 OR MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {console} from "forge-std/console.sol";

contract PayeeFaultArbitrationBugTest is Test, BaseTestHelper {
    PaymentsTestHelpers helper;
    Payments payments;
    MockERC20 token;
    MockValidator validator;

    uint256 constant DEPOSIT_AMOUNT = 200 ether;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();
        token = MockERC20(address(helper.testToken()));

        // Create an validator that will reduce payment when payee fails
        validator = new MockValidator(MockValidator.ValidatorMode.REDUCE_AMOUNT);
        validator.configure(20); // Only approve 20% of requested payment (simulating payee fault)

        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
    }

    function testLockupReturnedWithFaultTermination() public {
        uint256 networkFee = payments.NETWORK_FEE();
        uint256 paymentRate = 5 ether;
        uint256 lockupPeriod = 12;
        uint256 fixedLockup = 10 ether;

        uint256 railId = helper.setupRailWithParameters(
            USER1, USER2, OPERATOR, paymentRate, lockupPeriod, fixedLockup, address(validator), SERVICE_FEE_RECIPIENT
        );

        uint256 expectedTotalLockup = fixedLockup + (paymentRate * lockupPeriod);

        console.log("\n=== FIXED LOCKUP TEST ===");
        console.log("Fixed lockup:", fixedLockup);
        console.log("Rate-based lockup:", paymentRate * lockupPeriod);
        console.log("Expected total lockup:", expectedTotalLockup);

        // SP fails immediately, terminate
        vm.prank(OPERATOR);
        payments.terminateRail(railId);

        // Verify that railTerminated was called on the validator with correct parameters
        assertTrue(validator.railTerminatedCalled(), "railTerminated should have been called");
        assertEq(validator.lastTerminatedRailId(), railId, "Incorrect railId passed to validator");
        assertEq(validator.lastTerminator(), OPERATOR, "Incorrect terminator passed to validator");

        // Get the rail to verify the endEpoch matches
        Payments.RailView memory rail = payments.getRail(railId);
        assertEq(validator.lastEndEpoch(), rail.endEpoch, "Incorrect endEpoch passed to validator");

        helper.advanceBlocks(15);

        vm.prank(USER1);
        payments.settleRail{value: networkFee}(railId, block.number);

        Payments.Account memory payerFinal = helper.getAccountData(USER1);

        console.log("Lockup after:", payerFinal.lockupCurrent);
        console.log("Expected lockup:", expectedTotalLockup);

        require(payerFinal.lockupCurrent == 0, "Payee fault bug: Fixed lockup not fully returned");
    }

    function testLockupReturnedWithFault() public {
        uint256 networkFee = payments.NETWORK_FEE();
        uint256 paymentRate = 5 ether;
        uint256 lockupPeriod = 12;
        uint256 fixedLockup = 10 ether;

        uint256 railId = helper.setupRailWithParameters(
            USER1, USER2, OPERATOR, paymentRate, lockupPeriod, fixedLockup, address(validator), SERVICE_FEE_RECIPIENT
        );

        uint256 expectedTotalLockup = fixedLockup + (paymentRate * lockupPeriod);

        console.log("\n=== FIXED LOCKUP TEST ===");
        console.log("Fixed lockup:", fixedLockup);
        console.log("Rate-based lockup:", paymentRate * lockupPeriod);
        console.log("Expected total lockup:", expectedTotalLockup);

        vm.prank(OPERATOR);
        helper.advanceBlocks(15);

        vm.prank(USER1);
        payments.settleRail{value: networkFee}(railId, block.number);

        Payments.Account memory payerFinal = helper.getAccountData(USER1);

        console.log("Lockup after:", payerFinal.lockupCurrent);
        console.log("Expected lockup:", expectedTotalLockup);

        require(payerFinal.lockupCurrent == expectedTotalLockup, "Payee fault bug: Fixed lockup not fully returned");
    }

    function testLockupReturnedWithFaultReducedDuration() public {
        uint256 networkFee = payments.NETWORK_FEE();
        uint256 paymentRate = 5 ether;
        uint256 lockupPeriod = 12;
        uint256 fixedLockup = 10 ether;

        MockValidator dv = new MockValidator(MockValidator.ValidatorMode.REDUCE_DURATION);
        dv.configure(20); // Only approve 20% of requested duration

        uint256 railId = helper.setupRailWithParameters(
            USER1, USER2, OPERATOR, paymentRate, lockupPeriod, fixedLockup, address(dv), SERVICE_FEE_RECIPIENT
        );

        //  we will try to settle for 15 epochs, but the validator will only approve 20% of the duration i.e. 3 epochs
        // this means that funds for the remaining 12 epochs will still be locked up.
        uint256 expectedTotalLockup = fixedLockup + (paymentRate * lockupPeriod) + (12 * paymentRate);

        console.log("\n=== FIXED LOCKUP TEST ===");
        console.log("Fixed lockup:", fixedLockup);
        console.log("Rate-based lockup:", paymentRate * lockupPeriod);
        console.log("Expected total lockup:", expectedTotalLockup);

        vm.prank(OPERATOR);
        helper.advanceBlocks(15);

        vm.prank(USER1);
        payments.settleRail{value: networkFee}(railId, block.number);

        Payments.Account memory payerFinal = helper.getAccountData(USER1);

        console.log("Lockup after:", payerFinal.lockupCurrent);
        console.log("Expected lockup:", expectedTotalLockup);

        require(payerFinal.lockupCurrent == expectedTotalLockup, "Payee fault bug: Fixed lockup not fully returned");
    }
}
