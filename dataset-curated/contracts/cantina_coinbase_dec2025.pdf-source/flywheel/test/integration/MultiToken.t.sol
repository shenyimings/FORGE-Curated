// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../src/Constants.sol";
import {Flywheel} from "../../src/Flywheel.sol";
import {FlywheelTest} from "../lib/FlywheelTestBase.sol";
import {MockERC20} from "../lib/mocks/MockERC20.sol";

/// @title MultiTokenTest
/// @notice Tests for per-token isolation in Flywheel accounting and flows
contract MultiTokenTest is FlywheelTest {
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    function setUp() public {
        setUpFlywheelBase();

        // Create additional tokens for multi-token testing
        address[] memory holders = new address[](3);
        holders[0] = owner;
        holders[1] = manager;
        holders[2] = address(this);

        tokenA = new MockERC20(holders);
        tokenB = new MockERC20(holders);

        // Create and activate campaign
        campaign = createSimpleCampaign(owner, manager, "Multi Token Campaign", 1);
        activateCampaign(campaign, manager);

        // Fund campaign with both tokens (use max fuzz amount for sufficient funds)
        vm.prank(owner);
        tokenA.transfer(campaign, MAX_FUZZ_AMOUNT);
        vm.prank(owner);
        tokenB.transfer(campaign, MAX_FUZZ_AMOUNT);
    }

    /// @dev Allocate and distribute are isolated per token
    /// @dev Verifies balances and accounting do not cross-contaminate across tokens
    /// @param allocAmountA Amount to allocate for tokenA
    /// @param allocAmountB Amount to allocate for tokenB
    /// @param distAmountA Amount to distribute from tokenA allocation
    /// @param distAmountB Amount to distribute from tokenB allocation
    /// @param recipient1 First recipient address
    /// @param recipient2 Second recipient address
    function test_multiToken_allocateDistribute_isolatedPerToken(
        uint256 allocAmountA,
        uint256 allocAmountB,
        uint256 distAmountA,
        uint256 distAmountB,
        address recipient1,
        address recipient2
    ) public {
        // Bound inputs
        allocAmountA = boundToValidAmount(allocAmountA);
        allocAmountB = boundToValidAmount(allocAmountB);
        distAmountA = bound(distAmountA, 1, allocAmountA); // Must distribute <= allocated
        distAmountB = bound(distAmountB, 1, allocAmountB); // Must distribute <= allocated
        recipient1 = boundToValidPayableAddress(recipient1);
        recipient2 = boundToValidPayableAddress(recipient2);
        vm.assume(recipient1 != recipient2); // Ensure different recipients for different keys
        vm.assume(recipient1 != campaign); // Recipients should not be the campaign itself
        vm.assume(recipient2 != campaign);

        // Allocate to recipient1 using tokenA
        Flywheel.Payout[] memory payoutsA = buildSinglePayout(recipient1, allocAmountA, "");
        bytes memory allocDataA = abi.encode(payoutsA);
        vm.prank(manager);
        flywheel.allocate(campaign, address(tokenA), allocDataA);

        // Allocate to recipient2 using tokenB (different recipient to get different key)
        Flywheel.Payout[] memory payoutsB = buildSinglePayout(recipient2, allocAmountB, "");
        bytes memory allocDataB = abi.encode(payoutsB);
        vm.prank(manager);
        flywheel.allocate(campaign, address(tokenB), allocDataB);

        // MockCampaignHooksWithFees uses recipient address as key for allocations
        bytes32 actualKeyA = bytes32(bytes20(recipient1));
        bytes32 actualKeyB = bytes32(bytes20(recipient2));

        // Verify isolated allocation state
        assertEq(flywheel.allocatedPayout(campaign, address(tokenA), actualKeyA), allocAmountA);
        assertEq(flywheel.allocatedPayout(campaign, address(tokenA), actualKeyB), 0); // keyB not allocated for tokenA
        assertEq(flywheel.allocatedPayout(campaign, address(tokenB), actualKeyB), allocAmountB);
        assertEq(flywheel.allocatedPayout(campaign, address(tokenB), actualKeyA), 0); // keyA not allocated for tokenB

        assertEq(flywheel.totalAllocatedPayouts(campaign, address(tokenA)), allocAmountA);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(tokenB)), allocAmountB);

        // Record initial token balances
        uint256 recipient1InitialA = tokenA.balanceOf(recipient1);
        uint256 recipient1InitialB = tokenB.balanceOf(recipient1);
        uint256 recipient2InitialA = tokenA.balanceOf(recipient2);
        uint256 recipient2InitialB = tokenB.balanceOf(recipient2);

        // Distribute from keyA allocation (tokenA) to recipient1
        Flywheel.Payout[] memory distPayoutsA = buildSinglePayout(recipient1, distAmountA, "");
        bytes memory distDataA = abi.encode(distPayoutsA, new Flywheel.Distribution[](0), false);
        vm.prank(manager);
        flywheel.distribute(campaign, address(tokenA), distDataA);

        // Distribute from keyB allocation (tokenB) to recipient2
        Flywheel.Payout[] memory distPayoutsB = buildSinglePayout(recipient2, distAmountB, "");
        bytes memory distDataB = abi.encode(distPayoutsB, new Flywheel.Distribution[](0), false);
        vm.prank(manager);
        flywheel.distribute(campaign, address(tokenB), distDataB);

        // Verify isolated distribution effects
        // TokenA distribution should only affect tokenA balances and allocations
        assertEq(tokenA.balanceOf(recipient1), recipient1InitialA + distAmountA);
        assertEq(tokenA.balanceOf(recipient2), recipient2InitialA); // unchanged
        assertEq(flywheel.allocatedPayout(campaign, address(tokenA), actualKeyA), allocAmountA - distAmountA);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(tokenA)), allocAmountA - distAmountA);

        // TokenB distribution should only affect tokenB balances and allocations
        assertEq(tokenB.balanceOf(recipient2), recipient2InitialB + distAmountB);
        assertEq(tokenB.balanceOf(recipient1), recipient1InitialB); // unchanged
        assertEq(flywheel.allocatedPayout(campaign, address(tokenB), actualKeyB), allocAmountB - distAmountB);
        assertEq(flywheel.totalAllocatedPayouts(campaign, address(tokenB)), allocAmountB - distAmountB);

        // Cross-token contamination check: TokenB state should be unchanged by tokenA operations
        assertEq(flywheel.allocatedPayout(campaign, address(tokenB), actualKeyA), 0);
        assertEq(flywheel.allocatedPayout(campaign, address(tokenA), actualKeyB), 0);
    }

    /// @dev Send and distributeFees are isolated per token
    /// @dev Verifies allocations and fee collection per token without interference
    /// @param sendAmountA Amount to send via tokenA
    /// @param sendAmountB Amount to send via tokenB
    /// @param feeAmountA Fee amount for tokenA
    /// @param feeAmountB Fee amount for tokenB
    /// @param recipient1 First recipient address
    /// @param recipient2 Second recipient address
    /// @param feeRecipient Fee recipient address
    function test_multiToken_sendAndDistributeFees_isolatedPerToken(
        uint256 sendAmountA,
        uint256 sendAmountB,
        uint256 feeAmountA,
        uint256 feeAmountB,
        address recipient1,
        address recipient2,
        address feeRecipient
    ) public {
        // Bound inputs to reasonable amounts that won't exceed campaign balance
        // Campaign has MAX_FUZZ_AMOUNT of each token, so bound totals to stay within that
        sendAmountA = bound(sendAmountA, 1, MAX_FUZZ_AMOUNT / 4); // Leave room for fees
        sendAmountB = bound(sendAmountB, 1, MAX_FUZZ_AMOUNT / 4); // Leave room for fees
        feeAmountA = bound(feeAmountA, 0, MAX_FUZZ_AMOUNT / 4); // Fees can be 0, leave room for sends
        feeAmountB = bound(feeAmountB, 0, MAX_FUZZ_AMOUNT / 4); // Fees can be 0, leave room for sends
        recipient1 = boundToValidPayableAddress(recipient1);
        recipient2 = boundToValidPayableAddress(recipient2);
        feeRecipient = boundToValidPayableAddress(feeRecipient);

        // Ensure all recipients are different and not the campaign address
        vm.assume(recipient1 != recipient2);
        vm.assume(recipient1 != feeRecipient);
        vm.assume(recipient2 != feeRecipient);
        vm.assume(recipient1 != campaign);
        vm.assume(recipient2 != campaign);
        vm.assume(feeRecipient != campaign);

        bytes32 feeKey = keccak256("protocolFee");

        // Record initial balances
        uint256 recipient1InitialA = tokenA.balanceOf(recipient1);
        uint256 recipient1InitialB = tokenB.balanceOf(recipient1);
        uint256 recipient2InitialA = tokenA.balanceOf(recipient2);
        uint256 recipient2InitialB = tokenB.balanceOf(recipient2);
        uint256 feeRecipientInitialA = tokenA.balanceOf(feeRecipient);
        uint256 feeRecipientInitialB = tokenB.balanceOf(feeRecipient);

        // Send tokenA to recipient1 with fees to feeKey
        Flywheel.Payout[] memory sendPayoutsA = buildSinglePayout(recipient1, sendAmountA, "");
        Flywheel.Distribution[] memory feesA = new Flywheel.Distribution[](1);
        feesA[0] = Flywheel.Distribution({recipient: feeRecipient, key: feeKey, amount: feeAmountA, extraData: ""});
        bytes memory sendDataA = abi.encode(sendPayoutsA, feesA, false);
        vm.prank(manager);
        flywheel.send(campaign, address(tokenA), sendDataA);

        // Send tokenB to recipient2 with fees to same feeKey
        Flywheel.Payout[] memory sendPayoutsB = buildSinglePayout(recipient2, sendAmountB, "");
        Flywheel.Distribution[] memory feesB = new Flywheel.Distribution[](1);
        feesB[0] = Flywheel.Distribution({recipient: feeRecipient, key: feeKey, amount: feeAmountB, extraData: ""});
        bytes memory sendDataB = abi.encode(sendPayoutsB, feesB, false);
        vm.prank(manager);
        flywheel.send(campaign, address(tokenB), sendDataB);

        // Verify isolated send effects
        // TokenA send should only affect tokenA balances
        assertEq(tokenA.balanceOf(recipient1), recipient1InitialA + sendAmountA);
        assertEq(tokenA.balanceOf(recipient2), recipient2InitialA); // unchanged

        // TokenB send should only affect tokenB balances
        assertEq(tokenB.balanceOf(recipient2), recipient2InitialB + sendAmountB);
        assertEq(tokenB.balanceOf(recipient1), recipient1InitialB); // unchanged

        // Verify isolated fee allocation
        assertEq(flywheel.allocatedFee(campaign, address(tokenA), feeKey), feeAmountA);
        assertEq(flywheel.allocatedFee(campaign, address(tokenB), feeKey), feeAmountB);
        assertEq(flywheel.totalAllocatedFees(campaign, address(tokenA)), feeAmountA);
        assertEq(flywheel.totalAllocatedFees(campaign, address(tokenB)), feeAmountB);

        // Fees should not have been distributed yet
        assertEq(tokenA.balanceOf(feeRecipient), feeRecipientInitialA);
        assertEq(tokenB.balanceOf(feeRecipient), feeRecipientInitialB);

        // Distribute fees for tokenA only
        Flywheel.Distribution[] memory feeDistA = new Flywheel.Distribution[](1);
        feeDistA[0] = Flywheel.Distribution({recipient: feeRecipient, key: feeKey, amount: feeAmountA, extraData: ""});
        bytes memory feeDistDataA = abi.encode(feeDistA);
        vm.prank(manager);
        flywheel.distributeFees(campaign, address(tokenA), feeDistDataA);

        // Verify isolated fee distribution effects
        // TokenA fee distribution should only affect tokenA balances and allocations
        assertEq(tokenA.balanceOf(feeRecipient), feeRecipientInitialA + feeAmountA);
        assertEq(flywheel.allocatedFee(campaign, address(tokenA), feeKey), 0); // fees consumed
        assertEq(flywheel.totalAllocatedFees(campaign, address(tokenA)), 0);

        // TokenB fee state should remain unchanged
        assertEq(tokenB.balanceOf(feeRecipient), feeRecipientInitialB); // unchanged
        assertEq(flywheel.allocatedFee(campaign, address(tokenB), feeKey), feeAmountB); // still allocated
        assertEq(flywheel.totalAllocatedFees(campaign, address(tokenB)), feeAmountB);

        // Now distribute tokenB fees
        Flywheel.Distribution[] memory feeDistB = new Flywheel.Distribution[](1);
        feeDistB[0] = Flywheel.Distribution({recipient: feeRecipient, key: feeKey, amount: feeAmountB, extraData: ""});
        bytes memory feeDistDataB = abi.encode(feeDistB);
        vm.prank(manager);
        flywheel.distributeFees(campaign, address(tokenB), feeDistDataB);

        // Verify final state: both tokens' fees are now distributed
        assertEq(tokenB.balanceOf(feeRecipient), feeRecipientInitialB + feeAmountB);
        assertEq(flywheel.allocatedFee(campaign, address(tokenB), feeKey), 0);
        assertEq(flywheel.totalAllocatedFees(campaign, address(tokenB)), 0);

        // Total fees received should be the sum from both tokens
        assertEq(tokenA.balanceOf(feeRecipient), feeRecipientInitialA + feeAmountA);
        assertEq(tokenB.balanceOf(feeRecipient), feeRecipientInitialB + feeAmountB);
    }
}
