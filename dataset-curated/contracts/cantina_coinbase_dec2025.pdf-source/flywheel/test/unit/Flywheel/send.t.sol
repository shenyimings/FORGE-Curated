// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";

import {FailingERC20} from "../../lib/mocks/FailingERC20.sol";
import {RevertingReceiver} from "../../lib/mocks/RevertingReceiver.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title SendTest
/// @notice Tests for Flywheel.send
contract SendTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }

    /// @dev Expects CampaignDoesNotExist
    /// @dev Reverts when campaign does not exist
    /// @param token ERC20 token address under test
    /// @param hookData Raw hook data
    /// @param unknownCampaign Non-existent campaign address
    function test_reverts_whenCampaignDoesNotExist(address token, bytes memory hookData, address unknownCampaign)
        public
    {
        vm.assume(unknownCampaign != campaign);

        vm.expectRevert(Flywheel.CampaignDoesNotExist.selector);
        flywheel.send(unknownCampaign, token, hookData);
    }

    /// @dev Expects InvalidCampaignStatus
    /// @dev Reverts when campaign is INACTIVE
    /// @param token ERC20 token address under test
    /// @param hookData Raw hook data
    function test_reverts_whenCampaignInactive(address token, bytes memory hookData) public {
        // Campaign starts as INACTIVE by default
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.send(campaign, token, hookData);
    }

    /// @dev Expects InvalidCampaignStatus
    /// @dev Reverts when campaign is FINALIZED
    /// @param token ERC20 token address under test
    /// @param hookData Raw hook data
    function test_reverts_whenCampaignFinalized(address token, bytes memory hookData) public {
        activateCampaign(campaign, manager);
        finalizeCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.send(campaign, token, hookData);
    }

    /// @dev Expects SendFailed
    /// @dev Reverts when token transfer fails with an ERC20 token
    /// @param amount Payout amount
    /// @param recipient Recipient address
    /// @param eventTestData Extra data for the payout to attach in events
    function test_reverts_whenSendFailed_ERC20(uint256 amount, address recipient, bytes memory eventTestData) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        // Fund campaign with the failing token
        failingERC20.mint(campaign, amount);

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, eventTestData);
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectRevert(abi.encodeWithSelector(Flywheel.SendFailed.selector, address(failingERC20), recipient, amount));
        vm.prank(manager);
        flywheel.send(campaign, address(failingERC20), hookData);
    }

    /// @dev Expects SendFailed
    /// @dev Reverts when token transfer fails with native token
    /// @param amount Payout amount
    /// @param recipient Recipient address
    /// @param eventTestData Extra data for the payout to attach in events
    function test_reverts_whenSendFailed_nativeToken(uint256 amount, address recipient, bytes memory eventTestData)
        public
    {
        recipient = address(revertingRecipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, amount);

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, eventTestData);
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectRevert(abi.encodeWithSelector(Flywheel.SendFailed.selector, Constants.NATIVE_TOKEN, recipient, amount));
        vm.prank(manager);
        flywheel.send(campaign, Constants.NATIVE_TOKEN, hookData);
    }

    /// @dev Expects InsufficientCampaignFunds
    /// @dev Reverts when deferred fee allocation would place the campaign into insolvency
    /// @param amount Payout amount
    /// @param feeAmount Fee amount
    /// @param recipient Recipient address
    /// @param feeRecipient Fee recipient address
    /// @param eventTestData Extra data for the payout to attach in events
    function test_reverts_whenDeferredFeeAllocationPlacesCampaignIntoInsolvency(
        uint256 amount,
        uint256 feeAmount,
        address recipient,
        address feeRecipient,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign);
        vm.assume(feeRecipient != campaign);
        amount = boundToValidAmount(amount);
        feeAmount = boundToValidAmount(feeAmount);
        vm.assume(amount > 0 && feeAmount > 1);

        uint256 totalNeeded = amount + feeAmount;
        vm.assume(totalNeeded > amount); // Check for overflow

        activateCampaign(campaign, manager);
        // Fund campaign with just enough for payout but not enough for deferred fee allocation
        fundCampaign(campaign, totalNeeded - 1, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, eventTestData);
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, false); // Deferred fees

        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);
    }

    /// @dev Expects InsufficientCampaignFunds
    /// @dev Reverts when campaign is not solvent
    /// @param recipient Recipient address
    /// @param recipient2 Second recipient address
    /// @param amount Payout amount
    function test_reverts_whenCampaignIsNotSolvent(
        address recipient,
        address recipient2,
        uint256 amount,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        recipient2 = boundToValidPayableAddress(recipient2);
        vm.assume(recipient != campaign);
        vm.assume(recipient2 != campaign);
        vm.assume(recipient != recipient2);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);

        // Fund campaign with exact amount needed for allocation
        fundCampaign(campaign, amount, address(this));

        // Allocate all funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, eventTestData);
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now try to send additional amount - this should fail solvency check
        // because all funds are allocated but we're trying to send more
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient2, amount, eventTestData);
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that send calls are allowed when campaign is ACTIVE
    /// @param recipient Recipient address
    /// @param amount Payout amount
    function test_succeeds_whenCampaignActive(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers which don't change balance
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        assertEq(mockToken.balanceOf(campaign), 0);
    }

    /// @dev Verifies that send remains allowed when campaign is FINALIZING
    /// @param recipient Recipient address
    /// @param amount Payout amount
    function test_succeeds_whenCampaignFinalizing(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // Move to FINALIZING state
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        assertEq(mockToken.balanceOf(campaign), 0);
    }

    /// @dev Verifies that send calls work with an ERC20 token
    /// @param recipient Recipient address
    /// @param amount Payout amount
    function test_succeeds_withERC20Token(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        assertEq(mockToken.balanceOf(campaign), 0);
    }

    /// @dev Verifies that send calls work with native token
    /// @param recipient Recipient address
    /// @param amount Payout amount
    function test_succeeds_withNativeToken(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(recipient != address(vm)); // Avoid VM precompile that rejects ETH
        vm.assume(uint160(recipient) > 255); // Avoid precompile addresses (0x01-0xff)
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, amount);

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = recipient.balance;

        vm.prank(manager);
        flywheel.send(campaign, Constants.NATIVE_TOKEN, hookData);

        assertEq(recipient.balance, initialRecipientBalance + amount);
        assertEq(campaign.balance, 0);
    }

    /// @dev Ignores zero-amount payouts (no-op)
    /// @param recipient Recipient address
    /// @param amount Payout amount
    function test_ignoresZeroAmountPayouts(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount); // Fund with some amount, but send 0

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, 0, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        // Record logs to assert no PayoutSent event is emitted
        vm.recordLogs();
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        // Zero amount should not change recipient balance
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance);

        // Assert no PayoutSent event emitted by flywheel
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 payoutSentSig = keccak256("PayoutSent(address,address,address,uint256,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutSent = logs[i].topics.length > 0 && logs[i].topics[0] == payoutSentSig;
            if (isFromFlywheel && isPayoutSent) revert("PayoutSent was emitted for zero-amount payout");
        }
    }

    /// @dev Verifies that zero amount payouts are ignored when intermixed with non-zero amounts
    /// @param recipient1 First recipient address (will receive zero amount)
    /// @param recipient2 Second recipient address (will receive non-zero amount)
    /// @param amount Non-zero payout amount
    function test_ignoresZeroAmountPayouts_intermixedWithNonZero(
        address recipient1,
        address recipient2,
        uint256 amount
    ) public {
        recipient1 = boundToValidPayableAddress(recipient1);
        recipient2 = boundToValidPayableAddress(recipient2);
        vm.assume(recipient1 != recipient2);
        vm.assume(recipient1 != campaign); // Avoid self-transfers
        vm.assume(recipient2 != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0); // Ensure non-zero amount

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this)); // Only fund for the non-zero amount

        // Create payouts: one zero amount, one non-zero amount
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: 0, extraData: "zero_payout"});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount, extraData: "nonzero_payout"});

        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialBalance1 = mockToken.balanceOf(recipient1);
        uint256 initialBalance2 = mockToken.balanceOf(recipient2);

        // Record logs to verify only one PayoutSent event is emitted
        vm.recordLogs();
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        // Zero amount should not change recipient1 balance
        assertEq(mockToken.balanceOf(recipient1), initialBalance1);
        // Non-zero amount should change recipient2 balance
        assertEq(mockToken.balanceOf(recipient2), initialBalance2 + amount);

        // Verify only one PayoutSent event was emitted (for non-zero amount)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 payoutSentSig = keccak256("PayoutSent(address,address,address,uint256,bytes)");
        uint256 payoutSentCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutSent = logs[i].topics.length > 0 && logs[i].topics[0] == payoutSentSig;
            if (isFromFlywheel && isPayoutSent) payoutSentCount++;
        }
        assertEq(payoutSentCount, 1, "Should emit exactly one PayoutSent event for non-zero amount");
        assertEq(mockToken.balanceOf(campaign), 0);
    }

    /// @dev Verifies that send calls work with multiple payouts
    /// @param recipient1 First recipient address
    /// @param recipient2 Second recipient address
    /// @param amount1 First payout amount
    /// @param amount2 Second payout amount
    function test_succeeds_withMultiplePayouts(
        address recipient1,
        address recipient2,
        uint256 amount1,
        uint256 amount2
    ) public {
        recipient1 = boundToValidPayableAddress(recipient1);
        recipient2 = boundToValidPayableAddress(recipient2);
        vm.assume(recipient1 != recipient2);
        vm.assume(recipient1 != campaign); // Avoid self-transfers
        vm.assume(recipient2 != campaign); // Avoid self-transfers

        (amount1, amount2) = boundToValidMultiAmounts(amount1, amount2);
        uint256 totalAmount = amount1 + amount2;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalAmount, address(this));

        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: amount1, extraData: "payout1"});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount2, extraData: "payout2"});

        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialBalance1 = mockToken.balanceOf(recipient1);
        uint256 initialBalance2 = mockToken.balanceOf(recipient2);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient1), initialBalance1 + amount1);
        assertEq(mockToken.balanceOf(recipient2), initialBalance2 + amount2);
        assertEq(mockToken.balanceOf(campaign), 0);
    }

    /// @dev Verifies that send calls work with deferred fees (allocated, not sent)
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    function test_succeeds_withDeferredFees(address recipient, uint256 amount, uint256 feeBp, address feeRecipient)
        public
    {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        uint256 totalFunding = amount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, "fee");
        bytes memory hookData = buildSendHookData(payouts, fees, false); // Deferred fees

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        // Payout should be sent
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        // Fee should NOT be sent (deferred), but allocated
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), feeAmount);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), feeAmount);
        assertEq(mockToken.balanceOf(campaign), feeAmount);
    }

    /// @dev Verifies that send calls work with immediate fees (sent now if possible)
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    function test_succeeds_withImmediateFees(address recipient, uint256 amount, uint256 feeBp, address feeRecipient)
        public
    {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient != campaign); // Avoid campaign as fee recipient
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        uint256 totalFunding = amount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, "fee");
        bytes memory hookData = buildSendHookData(payouts, fees, true); // Immediate fees

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        // Payout should be sent
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        // Fee should be sent immediately
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance + feeAmount);
        // No allocated fees since they were sent immediately
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), 0);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), 0);
        assertEq(mockToken.balanceOf(campaign), 0);
    }

    /// @dev Verifies that allocated fees are updated when immediate fee send fails
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    function test_send_updatesAllocatedFees_onFeeSendFailure(
        address recipient,
        uint256 amount,
        uint256 feeBp,
        address feeRecipient
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(recipient != feeRecipient); // Avoid duplicate recipients
        // Force fee recipient to be address(0) to make fee transfer fail
        feeRecipient = address(0);
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        // Skip test if fee amount is zero (no allocation will occur)
        vm.assume(feeAmount > 0);
        activateCampaign(campaign, manager);
        // Fund for both payout and fee since fee will be allocated when transfer to address(0) fails
        uint256 totalFunding = amount + feeAmount;
        fundCampaign(campaign, totalFunding, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, "fee");
        bytes memory hookData = buildSendHookData(payouts, fees, true); // Try immediate fees

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        // Fee should NOT be sent (insufficient funds)
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance);
        // Fee should be allocated instead when send fails
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), feeAmount);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), feeAmount);
        assertEq(mockToken.balanceOf(campaign), feeAmount);
    }

    /// @dev Verifies that distribute skips fees of zero amount
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    function test_skipsFeesOfZeroAmount(address recipient, uint256 amount, uint256 feeBp, address feeRecipient) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient != campaign); // Avoid campaign as fee recipient
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        // Create fee with zero amount
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, 0, "zero_fee");
        bytes memory hookData = buildSendHookData(payouts, fees, true);

        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        // Record logs to assert no fee events are emitted
        vm.recordLogs();
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        // Zero fee should be skipped - no balance change or allocation
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance);
        assertEq(mockToken.balanceOf(campaign), 0);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), 0);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), 0);

        // Assert no FeeAllocated or FeeTransferFailed events emitted by flywheel
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 feeAllocatedSig = keccak256("FeeAllocated(address,address,bytes32,uint256,bytes)");
        bytes32 feeTransferFailedSig = keccak256("FeeTransferFailed(address,address,bytes32,address,uint256,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isFeeAllocated = logs[i].topics.length > 0 && logs[i].topics[0] == feeAllocatedSig;
            bool isFeeTransferFailed = logs[i].topics.length > 0 && logs[i].topics[0] == feeTransferFailedSig;
            if (isFromFlywheel && isFeeAllocated) revert("FeeAllocated was emitted for zero-amount fee");
            if (isFromFlywheel && isFeeTransferFailed) revert("FeeTransferFailed was emitted for zero-amount fee");
        }
    }

    /// @dev Verifies that send handles multiple fees in a single call
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    /// @param feeRecipient2 Second fee recipient address
    function test_send_handlesMultipleFees(
        address recipient,
        uint256 amount,
        uint256 feeBp,
        address feeRecipient,
        address feeRecipient2
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != feeRecipient2);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient != campaign); // Avoid campaign as fee recipient
        vm.assume(feeRecipient2 != address(0));
        vm.assume(feeRecipient2 != recipient);
        vm.assume(feeRecipient2 != feeRecipient);
        vm.assume(feeRecipient2 != campaign); // Avoid campaign as fee recipient
        vm.assume(feeRecipient != feeRecipient2); // Avoid duplicate fee recipients
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        feeRecipient2 = boundToValidPayableAddress(feeRecipient2);
        vm.assume(feeRecipient2 != feeRecipient);
        vm.assume(feeRecipient2 != campaign); // Avoid campaign as fee recipient

        // Prevent overflow when calculating total funding
        uint256 totalFees = feeAmount * 2;
        vm.assume(totalFees >= feeAmount); // Check for overflow
        uint256 totalFunding = amount + totalFees;
        vm.assume(totalFunding >= amount); // Check for overflow
        vm.assume(totalFunding <= MAX_FUZZ_AMOUNT); // Stay within limits

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");

        // Create multiple fees
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](2);
        fees[0] = Flywheel.Distribution({
            recipient: feeRecipient, key: bytes32(bytes20(feeRecipient)), amount: feeAmount, extraData: "fee1"
        });
        fees[1] = Flywheel.Distribution({
            recipient: feeRecipient2, key: bytes32(bytes20(feeRecipient2)), amount: feeAmount, extraData: "fee2"
        });

        bytes memory hookData = buildSendHookData(payouts, fees, true);

        uint256 initialBalance1 = mockToken.balanceOf(feeRecipient);
        uint256 initialBalance2 = mockToken.balanceOf(feeRecipient2);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);

        // Both fees should be sent
        assertEq(mockToken.balanceOf(feeRecipient), initialBalance1 + feeAmount);
        assertEq(mockToken.balanceOf(feeRecipient2), initialBalance2 + feeAmount);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(feeRecipient))), 0);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(feeRecipient2))), 0);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), 0);
        assertEq(mockToken.balanceOf(campaign), 0);
    }

    /// @dev Verifies that the PayoutSent event is emitted for each payout
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param eventTestData Extra data for the payout to attach in events
    function test_emitsPayoutSentEvent(address recipient, uint256 amount, bytes memory eventTestData) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, eventTestData);
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutSent(campaign, address(mockToken), recipient, amount, eventTestData);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeSent event is emitted on successful immediate fee send
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    /// @param eventTestData Extra data for the fee to attach in events
    function test_emitsFeeSentEvent_ifFeeSendSucceeds(
        address recipient,
        uint256 amount,
        uint256 feeBp,
        address feeRecipient,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        // Skip test if fee amount is zero (no event will be emitted)
        vm.assume(feeAmount > 0);
        uint256 totalFunding = amount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeSent(campaign, address(mockToken), feeRecipient, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeTransferFailed event is emitted on failed immediate fee send
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    /// @param eventTestData Extra data for the fee to attach in events
    function test_emitsFeeTransferFailedEvent_ifFeeSendFails(
        address recipient,
        uint256 amount,
        uint256 feeBp,
        address feeRecipient,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        // Use zero address for fee recipient to force transfer failure
        feeRecipient = address(0);
        vm.assume(recipient != feeRecipient);
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        // Skip test if fee amount is zero (no event will be emitted)
        vm.assume(feeAmount > 0);

        activateCampaign(campaign, manager);
        // Fund exactly the fee amount - this satisfies solvency but fee send will still fail
        // due to a deliberate setup to make the fee transfer fail
        fundCampaign(campaign, feeAmount, address(this));

        // Empty payouts array to avoid payout failures - we only want to test fee failure
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](0);
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true); // Try immediate fee send which will fail

        // Expect both FeeTransferFailed and FeeAllocated events when immediate fee send fails
        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeTransferFailed(campaign, address(mockToken), feeKey, feeRecipient, feeAmount, eventTestData);
        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeAllocated(campaign, address(mockToken), feeKey, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeAllocated event is emitted when immediate fee send fails
    /// @param amount Payout amount
    /// @param recipient Recipient address
    /// @param feeBp Fee basis points
    /// @param eventTestData Extra data for the fee to attach in events
    function test_emitsFeeAllocatedEvent_ifFeeSendFails_send(
        uint256 amount,
        address recipient,
        uint256 feeBp,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        // Use zero address for fee recipient to force transfer failure
        address feeRecipient = address(0);
        vm.assume(recipient != feeRecipient);
        // Use zero address for fee recipient to force transfer failure
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        // Skip test if fee amount is zero (no event will be emitted)
        vm.assume(feeAmount > 0);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, feeAmount, address(this));

        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](0);
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeAllocated(campaign, address(mockToken), feeKey, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeAllocated event is emitted for deferred fees
    /// @param recipient Recipient address
    /// @param amount Payout amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    /// @param eventTestData Extra data for the fee to attach in events
    function test_emitsFeeAllocatedEvent_forDeferredFees(
        address recipient,
        uint256 amount,
        uint256 feeBp,
        address feeRecipient,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);
        // Skip test if fee amount is zero (no event will be emitted)
        vm.assume(feeAmount > 0);

        uint256 totalFunding = amount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, false); // Deferred fees

        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeAllocated(campaign, address(mockToken), feeKey, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), hookData);
    }
}
