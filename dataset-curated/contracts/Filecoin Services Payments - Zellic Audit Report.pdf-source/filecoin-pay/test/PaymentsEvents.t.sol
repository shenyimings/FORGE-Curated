// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test, Vm} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

/**
 * @title PaymentsEventsTest
 * @dev Test contract for verifying all events emitted by the Payments contract
 */
contract PaymentsEventsTest is Test, BaseTestHelper {
    Payments public payments;
    PaymentsTestHelpers public helper;
    IERC20 public testToken;

    uint256 constant DEPOSIT_AMOUNT = 100 ether;
    uint256 constant MAX_LOCKUP_PERIOD = 100;
    uint256 railId;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();
        testToken = helper.testToken();

        // Setup operator approval
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            10 ether, // rateAllowance
            100 ether, // lockupAllowance
            MAX_LOCKUP_PERIOD // maxLockupPeriod
        );

        // Deposit funds for client
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
    }

    /**
     * @dev Test for AccountLockupSettled event
     */
    function testAccountLockupSettledEvent() public {
        // Create a rail to trigger account lockup changes
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set up rail parameters which will trigger account settlement
        vm.startPrank(OPERATOR);

        payments.modifyRailLockup(railId, 5, 0 ether);

        // This will trigger account lockup settlement
        // account.lockupCurrent = rate * period = 25 ether
        payments.modifyRailPayment(railId, 5 ether, 0); // 1 ether per block

        vm.stopPrank();

        helper.advanceBlocks(5);

        vm.startPrank(OPERATOR);

        // Expect the event to be emitted
        // lockupCurrent = 25 ether ( from modifyRailPayment ) + 5 * 5 ether ( elapsedTime * lockupRate)
        vm.expectEmit(true, true, true, true);
        emit Payments.AccountLockupSettled(address(testToken), USER1, 50 ether, 5 ether, block.number);
        emit Payments.RailLockupModified(railId, 5, 10, 0, 0);

        payments.modifyRailLockup(railId, 10, 0 ether);

        vm.stopPrank();
    }

    /**
     * @dev Test for OperatorApprovalSet event
     */
    function testOperatorApprovalUpdatedEvent() public {
        vm.startPrank(USER1);

        // Expect the event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Payments.OperatorApprovalUpdated(
            address(testToken), USER1, OPERATOR2, true, 5 ether, 50 ether, MAX_LOCKUP_PERIOD
        );

        // Set operator approval
        payments.setOperatorApproval(
            address(testToken),
            OPERATOR2,
            true,
            5 ether, // rateAllowance
            50 ether, // lockupAllowance
            MAX_LOCKUP_PERIOD // maxLockupPeriod
        );

        vm.stopPrank();
    }

    /**
     * @dev Test for RailCreated event
     */
    function testRailCreatedEvent() public {
        vm.startPrank(OPERATOR);

        // Expect the event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Payments.RailCreated(
            1, // railId (assuming this is the first rail)
            USER1, // payer
            USER2, // payee
            address(testToken), // token
            OPERATOR, // operator
            address(0), // validator
            SERVICE_FEE_RECIPIENT, // serviceFeeRecipient
            0 // commissionRateBps
        );

        // Create rail
        payments.createRail(
            address(testToken),
            USER1,
            USER2,
            address(0), // validator
            0, // commissionRateBps
            SERVICE_FEE_RECIPIENT // serviceFeeRecipient
        );

        vm.stopPrank();
    }

    /**
     * @dev Test for RailLockupModified event
     */
    function testRailLockupModifiedEvent() public {
        // Create a rail first
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        vm.startPrank(OPERATOR);

        // Expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit Payments.RailLockupModified(railId, 0, 10, 0, 10 ether);

        // Modify rail lockup
        payments.modifyRailLockup(railId, 10, 10 ether);

        vm.stopPrank();
    }

    /**
     * @dev Test for RailOneTimePayment event
     */
    function testRailOneTimePaymentEvent() public {
        // Create a rail first
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set up rail parameters
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 1 ether, 0);
        payments.modifyRailLockup(railId, 10, 10 ether);

        // calcualate expected values
        Payments.RailView memory rail = payments.getRail(railId);
        uint256 oneTimeAmount = 5 ether;
        uint256 expectedOperatorCommission = (oneTimeAmount * rail.commissionRateBps) / payments.COMMISSION_MAX_BPS();
        uint256 expectedNetPayeeAmount = oneTimeAmount - expectedOperatorCommission;

        // expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit Payments.RailOneTimePaymentProcessed(railId, expectedNetPayeeAmount, expectedOperatorCommission);

        // Execute one-time payment by calling modifyRailPayment with the current rate and a one-time payment amount

        payments.modifyRailPayment(railId, 1 ether, oneTimeAmount);

        vm.stopPrank();
    }

    /**
     * @dev Test for RailPaymentRateModified event
     */
    function testRailPaymentRateModifiedEvent() public {
        // Create a rail first
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        vm.startPrank(OPERATOR);

        // Expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit Payments.RailRateModified(railId, 0, 1 ether);

        // Modify rail payment rate
        payments.modifyRailPayment(railId, 1 ether, 0);

        vm.stopPrank();
    }

    /**
     * @dev Test for RailSettled event
     */
    function testRailSettledEvent() public {
        uint256 networkFee = payments.NETWORK_FEE();
        // Create and set up a rail
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 1 ether, 0);
        payments.modifyRailLockup(railId, 10, 10 ether);
        vm.stopPrank();

        // Advance blocks to accumulate payment
        helper.advanceBlocks(5);

        vm.startPrank(USER1);

        // expected values
        Payments.RailView memory rail = payments.getRail(railId);
        uint256 totalSettledAmount = 5 * rail.paymentRate;
        uint256 totalOperatorCommission = (totalSettledAmount * rail.commissionRateBps) / payments.COMMISSION_MAX_BPS();
        uint256 totalNetPayeeAmount = totalSettledAmount - totalOperatorCommission;

        // Expect the event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Payments.RailSettled(
            railId, totalSettledAmount, totalNetPayeeAmount, totalOperatorCommission, block.number
        );

        // Settle rail
        payments.settleRail{value: networkFee}(railId, block.number);

        vm.stopPrank();
    }

    /**
     * @dev Test for RailTerminated event
     */
    function testRailTerminatedEvent() public {
        // Create and set up a rail
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 1 ether, 0);
        payments.modifyRailLockup(railId, 10, 10 ether);
        vm.stopPrank();

        vm.startPrank(USER1);

        // expected end epoch
        Payments.RailView memory rail = payments.getRail(railId);
        uint256 expectedEndEpoch = block.number + rail.lockupPeriod;
        // Expect the event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Payments.RailTerminated(railId, USER1, expectedEndEpoch);

        // Terminate rail
        payments.terminateRail(railId);

        vm.stopPrank();
    }

    /**
     * @dev Test for RailFinalized event
     */
    function testRailFinalizedEvent() public {
        // Create and set up a rail
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 1 ether, 0);
        payments.modifyRailLockup(railId, 10, 10 ether);
        vm.stopPrank();

        // Terminate the rail
        vm.startPrank(USER1);
        payments.terminateRail(railId);
        vm.stopPrank();

        // Get the rail to check its end epoch
        Payments.RailView memory rail = payments.getRail(railId);

        // Advance blocks past the end epoch
        helper.advanceBlocks(rail.lockupPeriod + 1);

        vm.startPrank(USER1);

        // Expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit Payments.RailFinalized(railId);

        // Settle terminated rail to trigger finalization
        payments.settleTerminatedRailWithoutValidation(railId);

        vm.stopPrank();
    }

    /**
     * @dev Test for DepositRecorded event
     */
    function testDepositRecordedEvent() public {
        vm.startPrank(USER1);

        // Make sure we have approval
        testToken.approve(address(payments), 10 ether);

        // Expect the event to be emitted
        // Only check the first three indexed parameters
        vm.expectEmit(true, true, true, true);
        emit Payments.AccountLockupSettled(address(testToken), USER2, 0, 0, block.number);
        emit Payments.DepositRecorded(address(testToken), USER1, USER2, 10 ether, false); // Amount not checked

        // Deposit tokens
        payments.deposit(address(testToken), USER2, 10 ether);

        vm.stopPrank();

        // Test event in DepositWithPermit
        // Use a private key for signing
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);

        // Mint tokens to the signer
        MockERC20(address(testToken)).mint(signer, 50 ether);

        uint256 depositAmount = 10 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // Get signature components
        (uint8 v, bytes32 r, bytes32 s) =
            helper.getPermitSignature(privateKey, signer, address(payments), depositAmount, deadline);

        vm.startPrank(signer);

        // Expect the event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Payments.AccountLockupSettled(address(testToken), signer, 0, 0, block.number);
        emit Payments.DepositRecorded(address(testToken), signer, signer, depositAmount, true);

        // Deposit with permit
        payments.depositWithPermit(address(testToken), signer, depositAmount, deadline, v, r, s);

        vm.stopPrank();
    }

    /**
     * @dev Test for WithdrawRecorded event
     */
    function testWithdrawRecordedEvent() public {
        // First make a deposit to USER2
        helper.makeDeposit(USER1, USER2, 10 ether);

        vm.startPrank(USER2);

        // Expect the event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Payments.WithdrawRecorded(address(testToken), USER2, USER2, 5 ether);

        // Withdraw tokens
        payments.withdraw(address(testToken), 5 ether);

        vm.stopPrank();
    }
}
