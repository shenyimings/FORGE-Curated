// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";

import {FailingERC20} from "../../lib/mocks/FailingERC20.sol";
import {RevertingReceiver} from "../../lib/mocks/RevertingReceiver.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DistributeFeesTest
/// @notice Tests for Flywheel.distributeFees
contract DistributeFeesTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }
    /// @dev Expects CampaignDoesNotExist
    /// @dev Reverts when campaign does not exist
    /// @param token ERC20 token address under test
    /// @param unknownCampaign Non-existent campaign address

    function test_reverts_whenCampaignDoesNotExist(address token, address unknownCampaign) public {
        vm.assume(unknownCampaign != campaign);

        Flywheel.Distribution[] memory distributions = new Flywheel.Distribution[](0);
        bytes memory hookData = abi.encode(distributions);

        vm.expectRevert(Flywheel.CampaignDoesNotExist.selector);
        flywheel.distributeFees(unknownCampaign, token, hookData);
    }

    /// @dev Expects InsufficientCampaignFunds
    /// @dev Reverts when campaign is not solvent
    /// @param recipient Fee recipient address
    /// @param amount Fee amount
    function test_reverts_ifCampaignIsNotSolvent_distributeFees(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 1); // Ensure we can do meaningful operations

        activateCampaign(campaign, manager);
        // Fund campaign with fee amount + 1 so later payout allocation succeeds
        fundCampaign(campaign, amount + 1, address(this));

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, "fee");
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Verify fee was allocated and campaign is solvent
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), amount);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), amount);
        assertEq(mockToken.balanceOf(campaign), amount + 1);

        // Allocate some payouts to make solvency tight
        address payoutRecipient = makeAddr("payoutRecipient");
        uint256 payoutAmount = 1; // Small amount
        Flywheel.Payout[] memory payouts = buildSinglePayout(payoutRecipient, payoutAmount, "payout");
        vm.prank(manager);
        flywheel.allocate(campaign, address(mockToken), abi.encode(payouts));

        // Force insolvency after successful allocation by draining 1 wei from campaign
        vm.prank(campaign);
        mockToken.transfer(address(0xdead), 1);

        // Now balance < totalAllocatedFees + totalAllocatedPayouts

        // Try to distribute fees - should fail solvency check
        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        vm.prank(manager);
        flywheel.distributeFees(campaign, address(mockToken), abi.encode(feeAllocations));
    }

    /// @dev Verifies fees distribution succeeds with an ERC20 token and clears allocated fee
    /// @param recipient Fee recipient address
    /// @param amount Fee amount
    function test_succeeds_withERC20Token(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);
        vm.assume(recipient != campaign);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, "fee");
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Verify fee was allocated
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), amount);

        // Now distribute the fees
        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

        vm.prank(manager);
        flywheel.distributeFees(campaign, address(mockToken), abi.encode(feeAllocations));

        // Verify fee was sent and allocation was cleared
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), 0);
        assertEq(flywheel.totalAllocatedFees(campaign, address(mockToken)), 0);
    }

    /// @dev Verifies fees distribution succeeds with native token and clears allocated fee
    /// @param recipient Fee recipient address
    /// @param amount Fee amount
    function test_succeeds_withNativeToken(address recipient, uint256 amount) public {
        // Use a simple, clean address to avoid any edge cases
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, amount);

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, "fee");
        vm.prank(manager);
        flywheel.send(campaign, Constants.NATIVE_TOKEN, abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Verify fee was allocated
        assertEq(flywheel.allocatedFee(campaign, Constants.NATIVE_TOKEN, feeKey), amount);

        // Now distribute the fees
        uint256 initialRecipientBalance = recipient.balance;

        vm.prank(manager);
        flywheel.distributeFees(campaign, Constants.NATIVE_TOKEN, abi.encode(feeAllocations));

        // Verify fee was sent and allocation was cleared
        assertEq(recipient.balance, initialRecipientBalance + amount);
        assertEq(flywheel.allocatedFee(campaign, Constants.NATIVE_TOKEN, feeKey), 0);
        assertEq(flywheel.totalAllocatedFees(campaign, Constants.NATIVE_TOKEN), 0);
    }

    /// @dev Keeps allocation when send fails with ERC20; emits failure
    /// @param amount Fee amount
    function test_keepsAllocation_onSendFailure_ERC20(uint256 amount) public {
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        // Use a failing ERC20 token that will cause transfers to fail
        address recipient = makeAddr("recipient");

        activateCampaign(campaign, manager);
        // Fund campaign with the failing token
        failingERC20.mint(campaign, amount);

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, "fee");
        vm.prank(manager);
        flywheel.send(campaign, address(failingERC20), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Verify fee was allocated
        assertEq(flywheel.allocatedFee(campaign, address(failingERC20), feeKey), amount);
        uint256 initialTotalAllocated = flywheel.totalAllocatedFees(campaign, address(failingERC20));

        // Now try to distribute the fees - should fail but keep allocation
        uint256 initialRecipientBalance = failingERC20.balanceOf(recipient);

        vm.prank(manager);
        flywheel.distributeFees(campaign, address(failingERC20), abi.encode(feeAllocations));

        // Verify fee was NOT sent and allocation was kept
        assertEq(failingERC20.balanceOf(recipient), initialRecipientBalance);
        assertEq(flywheel.allocatedFee(campaign, address(failingERC20), feeKey), amount);
        assertEq(flywheel.totalAllocatedFees(campaign, address(failingERC20)), initialTotalAllocated);
    }

    /// @dev Keeps allocation when send fails with native token; emits failure
    /// @param amount Fee amount
    function test_keepsAllocation_onSendFailure_nativeToken(uint256 amount) public {
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        address recipient = address(revertingRecipient);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, amount);

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, "fee");
        vm.prank(manager);
        flywheel.send(campaign, Constants.NATIVE_TOKEN, abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Verify fee was allocated
        assertEq(flywheel.allocatedFee(campaign, Constants.NATIVE_TOKEN, feeKey), amount);
        uint256 initialTotalAllocated = flywheel.totalAllocatedFees(campaign, Constants.NATIVE_TOKEN);

        // Now try to distribute the fees - should fail but keep allocation
        uint256 initialRecipientBalance = recipient.balance;

        vm.prank(manager);
        flywheel.distributeFees(campaign, Constants.NATIVE_TOKEN, abi.encode(feeAllocations));

        // Verify fee was NOT sent and allocation was kept
        assertEq(recipient.balance, initialRecipientBalance);
        assertEq(flywheel.allocatedFee(campaign, Constants.NATIVE_TOKEN, feeKey), amount);
        assertEq(flywheel.totalAllocatedFees(campaign, Constants.NATIVE_TOKEN), initialTotalAllocated);
    }

    /// @notice Ignores zero-amount fee distributions (no-op)
    /// @dev Verifies totals unchanged and no send attempt for zero amounts
    /// @param recipient Fee recipient address
    /// @param amount Fee amount
    function test_ignoresZeroAmountDistributions(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount); // Fund with some amount, but distribute 0
        vm.assume(amount > 0);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, "fee");
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Now try to distribute zero amount fees
        Flywheel.Distribution[] memory zeroDistributions = buildSingleFee(recipient, feeKey, 0, "zero_fee");

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialAllocatedAmount = flywheel.allocatedFee(campaign, address(mockToken), feeKey);

        vm.recordLogs();
        vm.prank(manager);
        flywheel.distributeFees(campaign, address(mockToken), abi.encode(zeroDistributions));

        // Zero amount should not change recipient balance or allocations
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), feeKey), initialAllocatedAmount);

        // Assert no FeeDistributed event emitted by flywheel
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 FeeDistributedSig = keccak256("FeeDistributed(address,address,bytes32,address,uint256,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isFeeDistributed = logs[i].topics.length > 0 && logs[i].topics[0] == FeeDistributedSig;
            if (isFromFlywheel && isFeeDistributed) {
                revert("FeeDistributed was emitted for zero-amount fee distribution");
            }
        }
    }

    /// @dev Verifies that zero amount fee distributions are ignored when intermixed with non-zero amounts
    /// @param recipient1 First recipient address (will receive zero amount)
    /// @param recipient2 Second recipient address (will receive non-zero amount)
    /// @param amount Non-zero fee amount
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

        // First allocate fees to both recipients (only fund for recipient2's non-zero amount)
        Flywheel.Distribution[] memory feeAllocations = new Flywheel.Distribution[](2);
        feeAllocations[0] = Flywheel.Distribution({
            recipient: recipient1, key: bytes32(bytes20(recipient1)), amount: 0, extraData: "zero_fee_allocation"
        });
        feeAllocations[1] = Flywheel.Distribution({
            recipient: recipient2,
            key: bytes32(bytes20(recipient2)),
            amount: amount,
            extraData: "nonzero_fee_allocation"
        });

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Create distributions: one zero amount, one non-zero amount
        Flywheel.Distribution[] memory distributions = new Flywheel.Distribution[](2);
        distributions[0] = Flywheel.Distribution({
            recipient: recipient1, key: bytes32(bytes20(recipient1)), amount: 0, extraData: "zero_fee_distribution"
        });
        distributions[1] = Flywheel.Distribution({
            recipient: recipient2,
            key: bytes32(bytes20(recipient2)),
            amount: amount,
            extraData: "nonzero_fee_distribution"
        });

        uint256 initialBalance1 = mockToken.balanceOf(recipient1);
        uint256 initialBalance2 = mockToken.balanceOf(recipient2);
        uint256 initialAllocation1 = flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient1)));
        flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient2)));

        // Record logs to verify only one FeeDistributed event is emitted
        vm.recordLogs();
        vm.prank(manager);
        flywheel.distributeFees(campaign, address(mockToken), abi.encode(distributions));

        // Zero amount should not change recipient1 balance or allocation
        assertEq(mockToken.balanceOf(recipient1), initialBalance1);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient1))), initialAllocation1);
        // Non-zero amount should change recipient2 balance and clear allocation
        assertEq(mockToken.balanceOf(recipient2), initialBalance2 + amount);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient2))), 0);

        // Verify only one FeeDistributed event was emitted (for non-zero amount)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 FeeDistributedSig = keccak256("FeeDistributed(address,address,bytes32,address,uint256,bytes)");
        uint256 FeeDistributedCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            bool isFromFlywheel = logs[i].emitter == address(flywheel);
            bool isFeeDistributed = logs[i].topics.length > 0 && logs[i].topics[0] == FeeDistributedSig;
            if (isFromFlywheel && isFeeDistributed) FeeDistributedCount++;
        }
        assertEq(FeeDistributedCount, 1, "Should emit exactly one FeeDistributed event for non-zero amount");
    }

    /// @dev Verifies multiple fee distributions in a single call
    /// @param recipient1 First recipient address
    /// @param recipient2 Second recipient address
    /// @param amount1 First fee amount
    /// @param amount2 Second fee amount
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
        vm.assume(amount1 > 0 && amount2 > 0);
        uint256 totalAmount = amount1 + amount2;

        activateCampaign(campaign, manager);
        fundCampaign(campaign, totalAmount, address(this));

        // First allocate fees to both recipients using send with deferred fees
        Flywheel.Distribution[] memory feeAllocations = new Flywheel.Distribution[](2);
        feeAllocations[0] = Flywheel.Distribution({
            recipient: recipient1, key: bytes32(bytes20(recipient1)), amount: amount1, extraData: "fee1"
        });
        feeAllocations[1] = Flywheel.Distribution({
            recipient: recipient2, key: bytes32(bytes20(recipient2)), amount: amount2, extraData: "fee2"
        });

        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Verify fees were allocated
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient1))), amount1);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient2))), amount2);

        // Now distribute the fees
        uint256 initialBalance1 = mockToken.balanceOf(recipient1);
        uint256 initialBalance2 = mockToken.balanceOf(recipient2);

        vm.prank(manager);
        flywheel.distributeFees(campaign, address(mockToken), abi.encode(feeAllocations));

        // Verify fees were sent and allocations were cleared
        assertEq(mockToken.balanceOf(recipient1), initialBalance1 + amount1);
        assertEq(mockToken.balanceOf(recipient2), initialBalance2 + amount2);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient1))), 0);
        assertEq(flywheel.allocatedFee(campaign, address(mockToken), bytes32(bytes20(recipient2))), 0);
    }

    /// @dev Verifies that FeeDistributed event is emitted on successful distribution
    /// @param recipient Fee recipient address
    /// @param amount Fee amount
    /// @param eventTestData Extra data for the fee to attach in events
    function test_emitsFeeDistributed(address recipient, uint256 amount, bytes memory eventTestData) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        activateCampaign(campaign, manager);
        fundCampaign(campaign, amount, address(this));

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, eventTestData);
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Now distribute the fees and expect the FeeDistributed event
        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeDistributed(campaign, address(mockToken), feeKey, recipient, amount, eventTestData);

        vm.prank(manager);
        flywheel.distributeFees(campaign, address(mockToken), abi.encode(feeAllocations));
    }

    /// @dev Verifies that FeeTransferFailed event is emitted on failed send
    /// @param recipient Fee recipient address
    /// @param amount Fee amount
    /// @param eventTestData Extra data for the fee to attach in events
    function test_emitsFeeTransferFailed(address recipient, uint256 amount, bytes memory eventTestData) public {
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        recipient = address(revertingRecipient);

        activateCampaign(campaign, manager);
        // Fund campaign with native token
        vm.deal(campaign, amount);

        // First allocate a fee using send with deferred fees
        bytes32 feeKey = bytes32(bytes20(recipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(recipient, feeKey, amount, eventTestData);
        vm.prank(manager);
        flywheel.send(campaign, Constants.NATIVE_TOKEN, abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Now try to distribute the fees and expect the FeeTransferFailed event
        vm.expectEmit(true, true, true, true);
        emit Flywheel.FeeTransferFailed(campaign, Constants.NATIVE_TOKEN, feeKey, recipient, amount, eventTestData);

        vm.prank(manager);
        flywheel.distributeFees(campaign, Constants.NATIVE_TOKEN, abi.encode(feeAllocations));
    }
}
