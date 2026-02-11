// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title AllocateTest
/// @notice Tests for Flywheel.allocate
contract AllocateTest is FlywheelTest {
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
        flywheel.allocate(unknownCampaign, token, hookData);
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
        flywheel.allocate(campaign, token, hookData);
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
        flywheel.allocate(campaign, token, hookData);
    }

    /// @dev Expects InsufficientCampaignFunds
    /// @dev Reverts if campaign is insufficiently funded
    /// @param recipient Recipient address
    /// @param amount Allocation amount
    function test_reverts_ifCampaignIsInsufficientlyFunded(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);

        // Campaign has no funds, so any allocation should fail
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");

        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        managerAllocate(campaign, address(mockToken), payouts);
    }

    /// @dev Verifies that allocate calls are allowed for campaign in ACTIVE state
    /// @param recipient Recipient address
    /// @param amount Allocation amount
    function test_succeeds_whenCampaignActive(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");

        // Should succeed when campaign is ACTIVE
        managerAllocate(campaign, address(mockToken), payouts);

        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), amount);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), amount);
    }

    /// @dev Verifies that allocate remains allowed for campaign in FINALIZING state
    /// @param recipient Recipient address
    /// @param amount Allocation amount
    function test_succeeds_whenCampaignFinalizing(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // Move to FINALIZING state
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");

        // Should succeed when campaign is FINALIZING
        managerAllocate(campaign, address(mockToken), payouts);

        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), amount);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), amount);
    }

    /// @dev Verifies that allocate calls work with an ERC20 token
    /// @param recipient Recipient address
    /// @param amount Allocation amount
    function test_succeeds_withERC20Token(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");

        managerAllocate(campaign, address(mockToken), payouts);

        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), amount);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), amount);
    }

    /// @dev Verifies that allocate calls work with native token
    /// @param recipient Recipient address
    /// @param amount Allocation amount
    function test_succeeds_withNativeToken(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);

        // Fund campaign with native token
        vm.deal(campaign, amount);

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "");

        managerAllocate(campaign, Constants.NATIVE_TOKEN, payouts);

        assertEq(flywheel.allocatedPayout(campaign, Constants.NATIVE_TOKEN, bytes32(bytes20(recipient))), amount);
        assertEq(flywheel.totalAllocatedPayouts(campaign, Constants.NATIVE_TOKEN), amount);
    }

    /// @dev Ignores zero-amount allocations (no-op)
    /// @dev Verifies totals for zero amounts
    /// @param recipient Recipient address
    /// @param amount Allocation amount
    function test_ignoresZeroAmountAllocations(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount); // Need some amount to fund campaign, but we'll allocate 0

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, 0, "");

        // Record logs to assert no PayoutAllocated event is emitted
        vm.recordLogs();

        managerAllocate(campaign, address(mockToken), payouts);

        // Zero amount allocations should not change state
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), 0);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), 0);

        // Assert no PayoutAllocated event emitted by flywheel
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 payoutAllocatedSig = keccak256("PayoutAllocated(address,address,bytes32,uint256,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutAllocated = logs[i].topics.length > 0 && logs[i].topics[0] == payoutAllocatedSig;
            if (isFromFlywheel && isPayoutAllocated) revert("PayoutAllocated was emitted for zero-amount allocation");
        }
    }

    /// @dev Verifies that zero amount allocations are ignored when intermixed with non-zero amounts
    /// @param recipient1 First recipient address (will receive zero amount)
    /// @param recipient2 Second recipient address (will receive non-zero amount)
    /// @param amount Non-zero allocation amount
    function test_ignoresZeroAmountAllocations_intermixedWithNonZero(
        address recipient1,
        address recipient2,
        uint256 amount
    ) public {
        recipient1 = boundToValidPayableAddress(recipient1);
        recipient2 = boundToValidPayableAddress(recipient2);
        vm.assume(recipient1 != recipient2);
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0); // Ensure non-zero amount

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this)); // Only fund for the non-zero amount

        // Create allocations: one zero amount, one non-zero amount
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: 0, extraData: "zero_allocation"});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount, extraData: "nonzero_allocation"});

        // Record logs to verify only one PayoutAllocated event is emitted
        vm.recordLogs();
        managerAllocate(campaign, address(mockToken), payouts);

        // Zero amount should not change recipient1 allocation
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1))), 0);
        // Non-zero amount should change recipient2 allocation
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2))), amount);
        // Total allocations should only reflect non-zero amount
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), amount);

        // Verify only one PayoutAllocated event was emitted (for non-zero amount)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 payoutAllocatedSig = keccak256("PayoutAllocated(address,address,bytes32,uint256,bytes)");
        uint256 payoutAllocatedCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutAllocated = logs[i].topics.length > 0 && logs[i].topics[0] == payoutAllocatedSig;
            if (isFromFlywheel && isPayoutAllocated) payoutAllocatedCount++;
        }
        assertEq(payoutAllocatedCount, 1, "Should emit exactly one PayoutAllocated event for non-zero amount");
    }

    /// @dev Verifies that allocate calls work with multiple allocations
    /// @param recipient1 First recipient address
    /// @param recipient2 Second recipient address
    /// @param amount1 First allocation amount
    /// @param amount2 Second allocation amount
    function test_succeeds_withMultipleAllocations(
        address recipient1,
        address recipient2,
        uint256 amount1,
        uint256 amount2
    ) public {
        recipient1 = boundToValidPayableAddress(recipient1);
        recipient2 = boundToValidPayableAddress(recipient2);
        vm.assume(recipient1 != recipient2);

        (amount1, amount2) = boundToValidMultiAmounts(amount1, amount2);

        uint256 totalAmount = amount1 + amount2;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalAmount, address(this));

        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: amount1, extraData: "payout1"});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount2, extraData: "payout2"});

        managerAllocate(campaign, address(mockToken), payouts);

        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1))), amount1);
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2))), amount2);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), totalAmount);
    }

    /// @dev Emits PayoutAllocated event
    /// @param recipient Recipient address
    /// @param amount Allocation amount
    /// @param eventTestData Extra data for the payout to attach in events
    function test_emitsPayoutAllocatedEvent(address recipient, uint256 amount, bytes memory eventTestData) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, eventTestData);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutAllocated(campaign, address(mockToken), bytes32(bytes20(recipient)), amount, eventTestData);

        managerAllocate(campaign, address(mockToken), payouts);
    }
}
