// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";

import {stdError} from "forge-std/StdError.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DeallocateTest
/// @notice Tests for Flywheel.deallocate
contract DeallocateTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }

    /// @dev Expects CampaignDoesNotExist
    /// @dev Reverts if campaign does not exist
    /// @param token ERC20 token address under test
    /// @param hookData Raw hook data
    /// @param unknownCampaign Non-existent campaign address
    function test_reverts_whenCampaignDoesNotExist(address token, bytes memory hookData, address unknownCampaign)
        public
    {
        vm.assume(unknownCampaign != campaign);

        vm.expectRevert(Flywheel.CampaignDoesNotExist.selector);
        flywheel.deallocate(unknownCampaign, token, hookData);
    }

    /// @dev Expects InvalidCampaignStatus
    /// @dev Reverts if campaign is INACTIVE
    /// @param token ERC20 token address under test
    /// @param hookData Raw hook data
    function test_reverts_whenCampaignInactive(address token, bytes memory hookData) public {
        // Campaign starts as INACTIVE by default
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.deallocate(campaign, token, hookData);
    }

    /// @dev Expects InvalidCampaignStatus
    /// @dev Reverts if campaign is FINALIZED
    /// @param token ERC20 token address under test
    /// @param hookData Raw hook data
    function test_reverts_whenCampaignFinalized(address token, bytes memory hookData) public {
        activateCampaign(campaign, manager);
        finalizeCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.deallocate(campaign, token, hookData);
    }

    /// @dev Reverts (underflow) when trying to deallocate more than allocated for the key
    /// @param recipient Recipient address
    /// @param allocateAmount Allocation amount
    /// @param deallocateAmount Deallocation amount (will be > allocateAmount)
    function test_reverts_whenOverdeallocateFromAllocation(
        address recipient,
        uint256 allocateAmount,
        uint256 deallocateAmount
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        allocateAmount = boundToValidAmount(allocateAmount);
        deallocateAmount = boundToValidAmount(deallocateAmount);
        vm.assume(allocateAmount > 0);
        vm.assume(deallocateAmount > allocateAmount); // Overdraw condition

        activateCampaign(campaign, manager);
        fundCampaign(campaign, allocateAmount, address(this));

        // Allocate amount
        Flywheel.Payout[] memory allocatedPayouts = buildSinglePayout(recipient, allocateAmount, "");
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Verify allocation
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), allocateAmount);

        Flywheel.Payout[] memory deallocatePayouts = buildSinglePayout(recipient, deallocateAmount, "");

        vm.expectRevert(stdError.arithmeticError); // Underflow when trying to subtract more than allocated
        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(deallocatePayouts));
    }

    /// @dev Verifies that deallocate succeeds even when campaign is initially insolvent
    /// @dev Deallocate cannot cause InsufficientCampaignFunds since it only reduces allocations
    /// @param amount Deallocation amount
    function test_reverts_ifCampaignIsInsufficientlyFunded(uint256 amount) public {
        address recipient = boundToValidPayableAddress(makeAddr("recipient"));
        amount = boundToValidAmount(amount);

        activateCampaign(campaign, manager);

        // Fund and allocate first
        fundCampaign(campaign, amount, address(this));
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, "payout");
        managerAllocate(campaign, address(mockToken), payouts);

        // Verify initial allocation
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), amount);

        // Now drain ALL funds to make campaign insolvent BEFORE deallocating
        vm.prank(campaign);
        mockToken.transfer(address(0xdead), amount);

        // Campaign now has 0 balance but amount allocated - insolvent
        // However, deallocate should still succeed because it reduces allocations, improving solvency
        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(payouts));

        // Verify deallocation was successful and campaign is now solvent
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), 0);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), 0);
    }

    /// @dev Verifies that deallocate calls are allowed for campaign in ACTIVE state
    /// @param allocateAmount Allocation amount
    /// @param deallocateAmount Deallocation amount
    function test_succeeds_whenCampaignActive(uint256 allocateAmount, uint256 deallocateAmount) public {
        address recipient = boundToValidPayableAddress(makeAddr("recipient"));
        allocateAmount = boundToValidAmount(allocateAmount);
        deallocateAmount = boundToValidAmount(deallocateAmount);
        vm.assume(allocateAmount > 0);
        vm.assume(deallocateAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, allocateAmount, "payout");
        managerAllocate(campaign, address(mockToken), payouts);

        // Verify allocation was successful
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), allocateAmount);

        // Now deallocate a partial amount
        Flywheel.Payout[] memory deallocatePayouts = buildSinglePayout(recipient, deallocateAmount, "deallocate");
        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(deallocatePayouts));

        // Verify deallocation was successful (remaining allocation = allocateAmount - deallocateAmount)
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))),
            allocateAmount - deallocateAmount
        );
    }

    /// @dev Verifies that deallocate remains allowed for campaign in FINALIZING state
    /// @param allocateAmount Allocation amount
    /// @param deallocateAmount Deallocation amount
    function test_succeeds_whenCampaignFinalizing(uint256 allocateAmount, uint256 deallocateAmount) public {
        address recipient = boundToValidPayableAddress(makeAddr("recipient"));
        allocateAmount = boundToValidAmount(allocateAmount);
        deallocateAmount = boundToValidAmount(deallocateAmount);
        vm.assume(allocateAmount > 0);
        vm.assume(deallocateAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, allocateAmount, "payout");
        managerAllocate(campaign, address(mockToken), payouts);

        // Move to FINALIZING state
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Now deallocate - should work in FINALIZING state
        Flywheel.Payout[] memory deallocatePayouts = buildSinglePayout(recipient, deallocateAmount, "deallocate");
        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(deallocatePayouts));

        // Verify deallocation was successful
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))),
            allocateAmount - deallocateAmount
        );
    }

    /// @dev Verifies that deallocate calls work with an ERC20 token
    /// @param allocateAmount Allocation amount
    /// @param deallocateAmount Deallocation amount
    function test_succeeds_withERC20Token(address recipient, uint256 allocateAmount, uint256 deallocateAmount) public {
        recipient = boundToValidPayableAddress(recipient);
        allocateAmount = boundToValidAmount(allocateAmount);
        deallocateAmount = boundToValidAmount(deallocateAmount);
        vm.assume(allocateAmount > 0);
        vm.assume(deallocateAmount <= allocateAmount);
        vm.assume(recipient != campaign);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, allocateAmount, "payout");
        managerAllocate(campaign, address(mockToken), payouts);

        // Verify initial allocation
        uint256 initialAllocated = flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient)));
        uint256 initialTotalAllocated = flywheel.totalAllocatedPayouts(campaign, address(mockToken));
        assertEq(initialAllocated, allocateAmount);
        assertEq(initialTotalAllocated, allocateAmount);

        // Now deallocate
        Flywheel.Payout[] memory deallocatePayouts = buildSinglePayout(recipient, deallocateAmount, "deallocate");
        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(deallocatePayouts));

        // Verify deallocation cleared the allocation
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))),
            allocateAmount - deallocateAmount
        );
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), allocateAmount - deallocateAmount);
    }

    /// @dev Verifies that deallocate calls work with native token
    /// @param allocateAmount Allocation amount
    /// @param deallocateAmount Deallocation amount
    function test_succeeds_withNativeToken(uint256 allocateAmount, uint256 deallocateAmount) public {
        address recipient = boundToValidPayableAddress(makeAddr("recipient"));
        allocateAmount = boundToValidAmount(allocateAmount);
        deallocateAmount = boundToValidAmount(deallocateAmount);
        vm.assume(allocateAmount > 0);
        vm.assume(deallocateAmount <= allocateAmount);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, allocateAmount);

        // First allocate the funds
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, allocateAmount, "payout");
        managerAllocate(campaign, Constants.NATIVE_TOKEN, payouts);

        // Verify initial allocation
        uint256 initialAllocated =
            flywheel.allocatedPayout(campaign, Constants.NATIVE_TOKEN, bytes32(bytes20(recipient)));
        uint256 initialTotalAllocated = flywheel.totalAllocatedPayouts(campaign, Constants.NATIVE_TOKEN);
        assertEq(initialAllocated, allocateAmount);
        assertEq(initialTotalAllocated, allocateAmount);

        // Now deallocate
        Flywheel.Payout[] memory deallocatePayouts = buildSinglePayout(recipient, deallocateAmount, "deallocate");
        vm.prank(manager);
        flywheel.deallocate(campaign, Constants.NATIVE_TOKEN, abi.encode(deallocatePayouts));

        // Verify deallocation cleared the allocation
        assertEq(
            flywheel.allocatedPayout(campaign, Constants.NATIVE_TOKEN, bytes32(bytes20(recipient))),
            allocateAmount - deallocateAmount
        );
        assertEq(flywheel.totalAllocatedPayouts(campaign, Constants.NATIVE_TOKEN), allocateAmount - deallocateAmount);
    }

    /// @notice Ignores zero-amount deallocations (no-op)
    /// @dev Verifies totals unchanged and no event for zero amounts using the deployed token
    function test_ignoresZeroAmountDeallocations(uint256 allocateAmount) public {
        address recipient = boundToValidPayableAddress(makeAddr("recipient"));
        allocateAmount = boundToValidAmount(allocateAmount);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, allocateAmount, address(this));

        // First allocate some funds
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, allocateAmount, "payout");
        managerAllocate(campaign, address(mockToken), payouts);

        // Store initial state
        uint256 initialAllocated = flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient)));
        uint256 initialTotalAllocated = flywheel.totalAllocatedPayouts(campaign, address(mockToken));

        // Now try to deallocate zero amount
        vm.recordLogs();
        Flywheel.Payout[] memory zeroPayouts = buildSinglePayout(recipient, 0, "zero_payout");
        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(zeroPayouts));

        // Verify zero amount deallocation had no effect
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), initialAllocated);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), initialTotalAllocated);

        // Assert no PayoutDeallocated event emitted by flywheel
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 PayoutDeallocatedSig = keccak256("PayoutDeallocated(address,address,bytes32,uint256,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutDeallocated = logs[i].topics.length > 0 && logs[i].topics[0] == PayoutDeallocatedSig;
            if (isFromFlywheel && isPayoutDeallocated) {
                revert("PayoutDeallocated was emitted for zero-amount deallocation");
            }
        }
    }

    /// @dev Verifies that zero amount deallocations are ignored when intermixed with non-zero amounts
    /// @param recipient1 First recipient address (will have zero amount deallocated)
    /// @param recipient2 Second recipient address (will have non-zero amount deallocated)
    /// @param amount Non-zero deallocation amount
    function test_ignoresZeroAmountDeallocations_intermixedWithNonZero(
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

        // First allocate funds to both recipients (only fund for recipient2's non-zero amount)
        Flywheel.Payout[] memory allocatedPayouts = new Flywheel.Payout[](2);
        allocatedPayouts[0] = Flywheel.Payout({recipient: recipient1, amount: 0, extraData: "zero_allocation"});
        allocatedPayouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount, extraData: "nonzero_allocation"});
        managerAllocate(campaign, address(mockToken), allocatedPayouts);

        // Create deallocations: one zero amount, one non-zero amount
        Flywheel.Payout[] memory deallocatePayouts = new Flywheel.Payout[](2);
        deallocatePayouts[0] = Flywheel.Payout({recipient: recipient1, amount: 0, extraData: "zero_deallocate"});
        deallocatePayouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount, extraData: "nonzero_deallocate"});

        uint256 initialAllocation1 =
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1)));
        uint256 initialAllocation2 =
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2)));

        // Record logs to verify only one PayoutDeallocated event is emitted
        vm.recordLogs();
        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(deallocatePayouts));

        // Zero amount should not change recipient1 allocation
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1))), initialAllocation1
        );
        // Non-zero amount should reduce recipient2 allocation
        assertEq(
            flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2))),
            initialAllocation2 - amount
        );
        // Total allocations should only reflect the non-zero deallocation
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), 0);

        // Verify only one PayoutDeallocated event was emitted (for non-zero amount)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 PayoutDeallocatedSig = keccak256("PayoutDeallocated(address,address,bytes32,uint256,bytes)");
        uint256 PayoutDeallocatedCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isPayoutDeallocated = logs[i].topics.length > 0 && logs[i].topics[0] == PayoutDeallocatedSig;
            if (isFromFlywheel && isPayoutDeallocated) PayoutDeallocatedCount++;
        }
        assertEq(PayoutDeallocatedCount, 1, "Should emit exactly one PayoutDeallocated event for non-zero amount");
    }

    /// @dev Verifies that deallocate calls work with multiple deallocations
    /// @param amount1 First deallocation amount
    /// @param amount2 Second deallocation amount
    function test_succeeds_withMultipleDeallocations(uint256 amount1, uint256 amount2) public {
        address recipient1 = boundToValidPayableAddress(makeAddr("recipient1"));
        address recipient2 = boundToValidPayableAddress(makeAddr("recipient2"));
        vm.assume(recipient1 != recipient2);

        (amount1, amount2) = boundToValidMultiAmounts(amount1, amount2);
        vm.assume(amount1 > 0 && amount2 > 0);
        uint256 totalAmount = amount1 + amount2;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalAmount, address(this));

        // First allocate funds to both recipients
        Flywheel.Payout[] memory allocPayouts = new Flywheel.Payout[](2);
        allocPayouts[0] = Flywheel.Payout({recipient: recipient1, amount: amount1, extraData: "payout1"});
        allocPayouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount2, extraData: "payout2"});
        managerAllocate(campaign, address(mockToken), allocPayouts);

        // Verify allocations
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1))), amount1);
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2))), amount2);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), totalAmount);

        // Now deallocate from both recipients
        Flywheel.Payout[] memory deallocPayouts = new Flywheel.Payout[](2);
        deallocPayouts[0] = Flywheel.Payout({recipient: recipient1, amount: amount1, extraData: "payout1"});
        deallocPayouts[1] = Flywheel.Payout({recipient: recipient2, amount: amount2, extraData: "payout2"});

        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(deallocPayouts));

        // Verify deallocations cleared all allocations
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient1))), 0);
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient2))), 0);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), 0);
    }

    /// @dev Verifies that deallocate succeeds when funded by multiple allocates
    /// @param recipient Recipient address
    /// @param allocateAmount1 First allocation amount
    /// @param allocateAmount2 Second allocation amount
    function test_succeeds_whenFundedByMultipleAllocates(
        address recipient,
        uint256 allocateAmount1,
        uint256 allocateAmount2
    ) public {
        recipient = boundToValidPayableAddress(recipient);
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

        // Now deallocate the full amount that was funded by multiple allocates
        Flywheel.Payout[] memory deallocatePayouts = buildSinglePayout(recipient, totalAllocated, "deallocate_all");

        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(deallocatePayouts));

        // Verify full amount was deallocated and allocation was cleared
        assertEq(flywheel.allocatedPayout(campaign, address(mockToken), bytes32(bytes20(recipient))), 0);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(mockToken)), 0);
    }

    /// @dev Verifies that the PayoutDeallocated event is emitted for each deallocation
    /// @param amount Deallocation amount
    /// @param recipient Recipient address
    /// @param eventTestData Extra data for the payout to attach in events
    function test_emitsPayoutDeallocatedEvent(uint256 amount, address recipient, bytes memory eventTestData) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // First allocate the funds
        Flywheel.Payout[] memory payouts = buildSinglePayout(recipient, amount, eventTestData);
        managerAllocate(campaign, address(mockToken), payouts);

        // Now deallocate and expect the PayoutDeallocated event
        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutDeallocated(
            campaign, address(mockToken), bytes32(bytes20(recipient)), amount, eventTestData
        );

        vm.prank(manager);
        flywheel.deallocate(campaign, address(mockToken), abi.encode(payouts));
    }
}
