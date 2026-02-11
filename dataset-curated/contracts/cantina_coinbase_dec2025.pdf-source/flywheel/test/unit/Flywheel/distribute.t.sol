// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";

import {FailingERC20} from "../../lib/mocks/FailingERC20.sol";
import {RevertingReceiver} from "../../lib/mocks/RevertingReceiver.sol";
import {stdError} from "forge-std/StdError.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DistributeTest
/// @notice Tests for Flywheel.distribute
contract DistributeTest is FlywheelTest {
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
        flywheel.distribute(unknownCampaign, token, hookData);
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
        flywheel.distribute(campaign, token, hookData);
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
        flywheel.distribute(campaign, token, hookData);
    }

    /// @dev Expects SendFailed
    /// @dev Reverts when token transfer fails with an ERC20 token
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    function test_reverts_whenSendFailed_ERC20(uint256 allocateAmount, uint256 distributeAmount) public {
        // Use a failing ERC20 token that will cause transfers to fail
        address recipient = makeAddr("recipient");
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        // Fund campaign with the failing token
        failingERC20.mint(campaign, allocateAmount);

        // First allocate the funds so the allocation exists
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        vm.prank(manager);
        flywheel.allocate(campaign, address(failingERC20), abi.encode(allocatedPayouts));

        // Try to distribute - allocation exists and campaign has tokens, but transfer will fail
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectRevert(
            abi.encodeWithSelector(Flywheel.SendFailed.selector, address(failingERC20), recipient, distributeAmount)
        );
        vm.prank(manager);
        flywheel.distribute(campaign, address(failingERC20), hookData);
    }

    /// @dev Expects SendFailed
    /// @dev Reverts when token transfer fails with native token
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    function test_reverts_whenSendFailed_nativeToken(uint256 allocateAmount, uint256 distributeAmount) public {
        address recipient = address(revertingRecipient);
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, allocateAmount);

        // First allocate the funds so the allocation exists
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, Constants.NATIVE_TOKEN, allocatedPayouts);

        // Try to distribute - allocation exists and campaign has funds, but recipient will reject transfer
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectRevert(
            abi.encodeWithSelector(Flywheel.SendFailed.selector, Constants.NATIVE_TOKEN, recipient, distributeAmount)
        );
        vm.prank(manager);
        flywheel.distribute(campaign, Constants.NATIVE_TOKEN, hookData);
    }

    /// @dev Reverts (underflow)when trying to distribute more than allocated for the key
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount (will be > allocateAmount)
    function test_reverts_whenOverdrawFromAllocation(
        address recipient,
        uint256 allocateAmount,
        uint256 distributeAmount
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(allocateAmount > 0);
        vm.assume(distributeAmount > allocateAmount); // Overdraw condition

        activateCampaign(campaign, manager);
        // Fund campaign with distribute amount to ensure solvency isn't the issue
        fundCampaign(campaign, distributeAmount, address(this));

        // Allocate smaller amount than we'll try to distribute
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Verify allocation
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), allocateAmount);

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectRevert(stdError.arithmeticError); // Underflow when trying to subtract more than allocated
        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);
    }

    /// @dev Expects InsufficientCampaignFunds
    /// @dev Reverts when campaign is not solvent
    /// @param recipient Recipient address
    /// @param feeRecipient Fee recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    /// @param feeAmount Fee amount
    function test_reverts_ifCampaignIsNotSolvent(
        address recipient,
        address feeRecipient,
        uint256 allocateAmount,
        uint256 distributeAmount,
        uint256 feeAmount
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Ensure recipient is not the campaign itself
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        feeAmount = boundToValidAmount(feeAmount);
        vm.assume(distributeAmount <= allocateAmount);
        feeRecipient = boundToValidPayableAddress(feeRecipient);

        activateCampaign(campaign, manager);

        // Fund campaign with exact amount for allocation
        fundCampaign(campaign, allocateAmount, address(this));

        // Allocate all funds to recipient
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Try to distribute with additional fees that would make campaign insolvent
        // Campaign has 'allocateAmount' tokens, allocated to recipient
        // After distributing 'distributeAmount', adding deferred fees will increase totalAllocatedFees
        // making final solvency check fail: 0 < totalAllocatedFees
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, "fee");
        bytes memory hookData = buildSendHookData(payouts, fees, false); // Deferred fees

        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that distribute calls are allowed when campaign is ACTIVE
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    function test_succeeds_whenCampaignActive(address recipient, uint256 allocateAmount, uint256 distributeAmount)
        public
    {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers which don't change balance
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + distributeAmount);
        // Allocation should be consumed after distribution
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))),
            allocateAmount - distributeAmount
        );
    }

    /// @dev Verifies that distribute remains allowed when campaign is FINALIZING
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    function test_succeeds_whenCampaignFinalizing(address recipient, uint256 allocateAmount, uint256 distributeAmount)
        public
    {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Move to FINALIZING state
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Now distribute
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + distributeAmount);
    }

    /// @dev Verifies that distribute calls work with an ERC20 token
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    function test_succeeds_withERC20Token(address recipient, uint256 allocateAmount, uint256 distributeAmount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);
        vm.assume(recipient != campaign);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + distributeAmount);
    }

    /// @dev Verifies that distribute calls work with native token
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    function test_succeeds_withNativeToken(address recipient, uint256 allocateAmount, uint256 distributeAmount) public {
        // Use a simple, clean address to avoid any edge cases
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, allocateAmount);

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, Constants.NATIVE_TOKEN, allocatedPayouts);

        // Now distribute
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = recipient.balance;

        vm.prank(manager);
        flywheel.distribute(campaign, Constants.NATIVE_TOKEN, hookData);

        assertEq(recipient.balance, initialRecipientBalance + distributeAmount);
    }

    /// @dev Verifies that distribute calls work with fees
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    function test_succeeds_withDeferredFees(
        address recipient,
        uint256 allocateAmount,
        uint256 distributeAmount,
        uint256 feeBp,
        address feeRecipient
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(distributeAmount, feeBpBounded);
        uint256 totalFunding = allocateAmount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with deferred fees
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, "fee");
        bytes memory hookData = buildSendHookData(payouts, fees, false); // Deferred fees

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Payout should be distributed
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + distributeAmount);
        // Fee should NOT be sent (deferred), but allocated
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), feeAmount);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), feeAmount);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), allocateAmount - distributeAmount);
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))),
            allocateAmount - distributeAmount
        );
    }

    /// @dev Verifies that distribute calls work with immediate fees
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    /// @param eventTestData Extra data for the fee to attach in events
    function test_succeeds_withImmediateFees_distribute(
        address recipient,
        uint256 allocateAmount,
        uint256 distributeAmount,
        uint256 feeBp,
        address feeRecipient,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient != campaign); // Avoid campaign as fee recipient
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(distributeAmount, feeBpBounded);
        uint256 totalFunding = allocateAmount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, eventTestData);
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with immediate fees
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, eventTestData);
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true); // Immediate fees

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Payout should be distributed
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + distributeAmount);
        // Fee should be sent immediately
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance + feeAmount);
        // No allocated fees since they were sent immediately
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), 0);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), 0);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), allocateAmount - distributeAmount);
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))),
            allocateAmount - distributeAmount
        );
    }

    /// @dev Verifies that distribute updates allocated fees on fee send failure
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeKey Fee key
    function test_updatesAllocatedFees_onFeeSendFailure(
        address recipient,
        uint256 allocateAmount,
        uint256 distributeAmount,
        uint256 feeBp,
        bytes32 feeKey,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        // Force fee recipient to be address(0) to make fee transfer fail
        address feeRecipient = address(0);
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(distributeAmount, feeBpBounded);
        // Skip test if fee amount is zero (no allocation will occur)
        vm.assume(feeAmount > 0);
        uint256 totalFunding = allocateAmount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with immediate fees that will fail
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true); // Try immediate fees

        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Fee should NOT be sent (transfer to address(0) fails)
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance);
        // Fee should be allocated instead when send fails
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), feeAmount);
    }

    /// @dev Verifies that distribute skips fees of zero amount
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param distributeAmount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    /// @param eventTestData Extra data for the fee to attach in events
    function test_skipsFeesOfZeroAmount(
        address recipient,
        uint256 allocateAmount,
        uint256 distributeAmount,
        uint256 feeBp,
        address feeRecipient,
        bytes memory eventTestData
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient != campaign); // Avoid campaign as fee recipient
        allocateAmount = boundToValidAmount(allocateAmount);
        distributeAmount = boundToValidAmount(distributeAmount);
        vm.assume(distributeAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with zero fees
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, distributeAmount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        // Create fee with zero amount
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, 0, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true);

        uint256 initialFeeRecipientBalance = mockToken.balanceOf(feeRecipient);

        // Record logs to assert no fee events are emitted
        vm.recordLogs();
        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Zero fee should be skipped - no balance change or allocation
        assertEq(mockToken.balanceOf(feeRecipient), initialFeeRecipientBalance);
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
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), allocateAmount - distributeAmount);
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))),
            allocateAmount - distributeAmount
        );
    }

    /// @dev Verifies that distribute handles multiple fees
    /// @param recipient Recipient address
    /// @param amount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient1 First fee recipient address
    /// @param feeRecipient2 Second fee recipient address
    function test_handlesMultipleFees(
        address recipient,
        uint256 amount,
        uint256 feeBp,
        address feeRecipient1,
        address feeRecipient2
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient1 = boundToValidPayableAddress(feeRecipient1);
        feeRecipient2 = boundToValidPayableAddress(feeRecipient2);
        vm.assume(recipient != feeRecipient1);
        vm.assume(recipient != feeRecipient2);
        vm.assume(feeRecipient1 != feeRecipient2);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient1 != campaign); // Avoid campaign as fee recipient
        vm.assume(feeRecipient2 != campaign); // Avoid campaign as fee recipient
        vm.assume(feeRecipient1 != feeRecipient2); // Avoid duplicate fee recipients
        amount = boundToValidAmount(amount);
        uint16 feeBpBounded = boundToValidFeeBp(feeBp);

        uint256 feeAmount = calculateFeeAmount(amount, feeBpBounded);

        // Prevent overflow when calculating total funding
        uint256 totalFees = feeAmount * 2;
        vm.assume(totalFees >= feeAmount); // Check for overflow
        uint256 totalFunding = amount + totalFees;
        vm.assume(totalFunding >= amount); // Check for overflow
        vm.assume(totalFunding <= MAX_FUZZ_AMOUNT); // Stay within limits

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with multiple fees
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");

        // Create multiple fees
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](2);
        fees[0] = Flywheel.Distribution({
            recipient: feeRecipient1, key: bytes32(bytes20(feeRecipient1)), amount: feeAmount, extraData: "fee1"
        });
        fees[1] = Flywheel.Distribution({
            recipient: feeRecipient2, key: bytes32(bytes20(feeRecipient2)), amount: feeAmount, extraData: "fee2"
        });

        bytes memory hookData = buildSendHookData(payouts, fees, true);

        uint256 initialBalance1 = mockToken.balanceOf(feeRecipient1);
        uint256 initialBalance2 = mockToken.balanceOf(feeRecipient2);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Both fees should be sent
        assertEq(mockToken.balanceOf(feeRecipient1), initialBalance1 + feeAmount);
        assertEq(mockToken.balanceOf(feeRecipient2), initialBalance2 + feeAmount);
    }

    /// @notice Ignores zero-amount distributions (no-op)
    /// @dev Verifies totals unchanged and no event for zero amounts using the deployed token
    /// @param recipient Recipient address
    /// @param amount Distribution amount
    function test_ignoresZeroAmountDistributions(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount); // Fund with some amount, but distribute 0

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // First allocate some funds (but we'll distribute zero)
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute zero amount
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, 0, "");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialAllocatedAmount =
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient)));

        // Record logs to assert no PayoutDistributed event is emitted
        vm.recordLogs();

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Zero amount should not change recipient balance or allocations
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance);
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), initialAllocatedAmount
        );

        // Assert no PayoutDistributed event emitted by flywheel
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 PayoutDistributedSig = keccak256("PayoutDistributed(address,address,bytes32,address,uint256,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutDistributed = logs[i].topics.length > 0 && logs[i].topics[0] == PayoutDistributedSig;
            if (isFromFlywheel && isPayoutDistributed) {
                revert("PayoutDistributed was emitted for zero-amount distribution");
            }
        }
    }

    /// @dev Verifies that zero amount distributions are ignored when intermixed with non-zero amounts
    /// @param recipient1 First recipient address (will receive zero amount)
    /// @param recipient2 Second recipient address (will receive non-zero amount)
    /// @param amount Non-zero distribution amount
    function test_ignoresZeroAmountDistributions_intermixedWithNonZero(
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

        // First allocate funds to both recipients (only fund for recipient2's non-zero amount)
        Flywheel.Payout[] memory allocatedPayouts = new Flywheel.Payout[](2);
        allocatedPayouts[0] = Flywheel.Payout({recipient: recipient1, amount: 0, extraData: "zero_allocation"});
        allocatedPayouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount, extraData: "nonzero_allocation"});
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Create distributions: one zero amount, one non-zero amount
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: 0, extraData: "zero_distribution"});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount, extraData: "nonzero_distribution"});

        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialBalance1 = mockToken.balanceOf(recipient1);
        uint256 initialBalance2 = mockToken.balanceOf(recipient2);

        // Record logs to verify only one PayoutDistributed event is emitted
        vm.recordLogs();
        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Zero amount should not change recipient1 balance
        assertEq(mockToken.balanceOf(recipient1), initialBalance1);
        // Non-zero amount should change recipient2 balance
        assertEq(mockToken.balanceOf(recipient2), initialBalance2 + amount);
        // Recipient1 allocation should remain unchanged (was 0, stays 0)
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1))), 0);
        // Recipient2 allocation should be consumed
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2))), 0);

        // Verify only one PayoutDistributed event was emitted (for non-zero amount)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 PayoutDistributedSig = keccak256("PayoutDistributed(address,address,bytes32,address,uint256,bytes)");
        uint256 PayoutDistributedCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutDistributed = logs[i].topics.length > 0 && logs[i].topics[0] == PayoutDistributedSig;
            if (isFromFlywheel && isPayoutDistributed) PayoutDistributedCount++;
        }
        assertEq(PayoutDistributedCount, 1, "Should emit exactly one PayoutDistributed event for non-zero amount");
    }

    /// @dev Verifies that distribute calls work with multiple distributions
    /// @param recipient1 First recipient address
    /// @param recipient2 Second recipient address
    /// @param amount1 First distribution amount
    /// @param amount2 Second distribution amount
    function test_succeeds_withMultipleDistributions(
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

        // First allocate funds to both recipients
        Flywheel.Payout[] memory allocatedPayouts = new Flywheel.Payout[](2);
        allocatedPayouts[0] = Flywheel.Payout({recipient: recipient1, amount: amount1, extraData: "payout1"});
        allocatedPayouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount2, extraData: "payout2"});
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute to both
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: amount1, extraData: "payout1"});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount2, extraData: "payout2"});

        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        uint256 initialBalance1 = mockToken.balanceOf(recipient1);
        uint256 initialBalance2 = mockToken.balanceOf(recipient2);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        assertEq(mockToken.balanceOf(recipient1), initialBalance1 + amount1);
        assertEq(mockToken.balanceOf(recipient2), initialBalance2 + amount2);
        // Allocations should be consumed
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1))), 0);
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2))), 0);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), 0);
    }

    /// @dev Verifies that distribute succeeds when funded by multiple allocates
    /// @param recipient Recipient address
    /// @param allocateAmount1 First allocation amount
    /// @param allocateAmount2 Second allocation amount
    function test_succeeds_whenFundedByMultipleAllocates(
        address recipient,
        uint256 allocateAmount1,
        uint256 allocateAmount2
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        (allocateAmount1, allocateAmount2) = boundToValidMultiAmounts(allocateAmount1, allocateAmount2);
        vm.assume(allocateAmount1 > 0 && allocateAmount2 > 0);
        uint256 totalAllocated = allocateAmount1 + allocateAmount2;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalAllocated, address(this));

        // First allocation
        Flywheel.Payout[] memory payouts1 = buildSinglePayout(recipient, allocateAmount1, "first_allocation");
        managerAllocate(campaign, address(mockToken), payouts1);

        // Verify first allocation
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), allocateAmount1);

        // Second allocation (adds to existing allocation)
        Flywheel.Payout[] memory payouts2 = buildSinglePayout(recipient, allocateAmount2, "second_allocation");
        managerAllocate(campaign, address(mockToken), payouts2);

        // Verify total allocation is sum of both allocates
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), totalAllocated);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), totalAllocated);

        // Now distribute the full amount that was funded by multiple allocates
        Flywheel.Payout[] memory distributePayouts = buildSinglePayout(recipient, totalAllocated, "distribute_all");
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(distributePayouts, fees, false);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);

        // Verify full amount was distributed and allocation was cleared
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + totalAllocated);
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), 0);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), 0);
    }

    /// @dev Verifies that the PayoutDistributed event is emitted for each distribution
    /// @param recipient Recipient address
    /// @param amount Distribution amount
    function test_emitsPayoutDistributedEvent(address recipient, uint256 amount, bytes memory eventTestData) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, eventTestData);
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, eventTestData);
        Flywheel.Distribution[] memory fees = new Flywheel.Distribution[](0);
        bytes memory hookData = buildSendHookData(payouts, fees, false);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutDistributed(
            campaign, address(mockToken), bytes32(bytes20(recipient)), recipient, amount, eventTestData
        );

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeSent event is emitted on successful immediate fee send
    /// @param recipient Recipient address
    /// @param amount Distribution amount
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

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with immediate fees
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeSent(campaign, address(mockToken), feeRecipient, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeTransferFailed event is emitted for each failed fee distribution
    /// @param recipient Recipient address
    /// @param amount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
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
        uint256 totalFunding = amount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with immediate fees that will fail
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true); // Try immediate fee send which will fail

        // Expect both FeeTransferFailed and FeeAllocated events when immediate fee send fails
        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeTransferFailed(campaign, address(mockToken), feeKey, feeRecipient, feeAmount, eventTestData);
        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeAllocated(campaign, address(mockToken), feeKey, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeAllocated event is emitted for each allocated fee
    /// @param recipient Recipient address
    /// @param amount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    function test_emitsFeeAllocatedEvent_ifFeeSendFails(
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
        uint256 totalFunding = amount + feeAmount;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalFunding, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with immediate fees that will fail and be allocated
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, true);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeAllocated(campaign, address(mockToken), feeKey, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeAllocated event is emitted for each deferred fee
    /// @param recipient Recipient address
    /// @param amount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
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

        // First allocate the funds
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Now distribute with deferred fees
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory fees = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        bytes memory hookData = buildSendHookData(payouts, fees, false); // Deferred fees

        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeAllocated(campaign, address(mockToken), feeKey, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.distribute(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies that the FeeDistributed event is emitted for each fee distribution
    /// @param recipient Recipient address
    /// @param amount Distribution amount
    /// @param feeBp Fee basis points
    /// @param feeRecipient Fee recipient address
    /// @param eventTestData Extra data for the fee to attach in events
    function test_emitsFeeDistributedEvent(
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

        // First allocate both payout and fee
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, amount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        // Allocate fee manually using distributeFees approach
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(feeRecipient, feeKey, feeAmount, eventTestData);
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Now use distributeFees to emit FeeDistributed event
        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeDistributed(campaign, address(mockToken), feeKey, feeRecipient, feeAmount, eventTestData);

        vm.prank(manager);
        flywheel.distributeFees(campaign, address(mockToken), abi.encode(feeAllocations));
    }
}
