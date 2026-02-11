// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

import {CashbackRewardsTest} from "../../../lib/CashbackRewardsTest.sol";

import {Flywheel} from "../../../../src/Flywheel.sol";
import {CashbackRewards} from "../../../../src/hooks/CashbackRewards.sol";
import {SimpleRewards} from "../../../../src/hooks/SimpleRewards.sol";

contract OnAllocateTest is CashbackRewardsTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not authorized manager
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate for the payment
    /// @param unauthorizedCaller Address that is not the campaign manager
    function test_revert_unauthorizedCaller(uint120 paymentAmount, uint120 allocateAmount, address unauthorizedCaller)
        public
    {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(unauthorizedCaller != manager && unauthorizedCaller != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, allocateAmount);

        authorizePayment(paymentInfo);

        vm.prank(unauthorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(SimpleRewards.Unauthorized.selector));
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to allocate zero amount
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_revert_zeroAmount(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        authorizePayment(paymentInfo);

        bytes memory hookData = createCashbackHookData(paymentInfo, 0);

        vm.expectRevert(CashbackRewards.ZeroPayoutAmount.selector);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when payment token differs from campaign token
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate for the payment
    /// @param wrongToken Incorrect token address used in payment
    function test_revert_wrongToken(uint120 paymentAmount, uint120 allocateAmount, address wrongToken) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        paymentInfo.token = wrongToken; // Payment expects wrongToken but we call with USDC

        bytes memory hookData = createCashbackHookData(paymentInfo, allocateAmount);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector));
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to allocate for payment that hasn't been collected
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate for the payment
    function test_revert_unauthorizedPayment(uint120 paymentAmount, uint120 allocateAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        // Don't authorize payment - should fail validation
        bytes memory hookData = createCashbackHookData(paymentInfo, allocateAmount);

        vm.expectRevert(CashbackRewards.PaymentNotCollected.selector);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when allocation exceeds maximum percentage limit for campaign
    /// @param paymentAmount Payment amount in USDC for the transaction (bounded to avoid overflow)
    function test_revert_maxRewardPercentageExceeded(uint120 paymentAmount) public {
        // Bound payment amount to reasonable range to avoid overflow in percentage calculations
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC to avoid overflow

        // Calculate max allowed amount (1% of payment)
        uint120 maxAllowedAmount = (paymentAmount * TEST_MAX_REWARD_BASIS_POINTS) / MAX_REWARD_BASIS_POINTS_DIVISOR;

        // Skip test if maxAllowedAmount would be 0 (payment too small)
        vm.assume(maxAllowedAmount > 0);

        uint120 excessRewardAmount = 1;
        uint120 excessiveAllocation = maxAllowedAmount + excessRewardAmount; // Just over the limit

        // Fund the restricted campaign for the test
        usdc.mint(manager, excessiveAllocation);
        vm.prank(manager);
        usdc.transfer(limitedCashbackCampaign, excessiveAllocation);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        bytes memory hookData = createCashbackHookData(paymentInfo, excessiveAllocation);

        authorizePayment(paymentInfo);

        vm.expectRevert(
            abi.encodeWithSelector(
                CashbackRewards.RewardExceedsMaxPercentage.selector,
                paymentInfoHash,
                maxAllowedAmount,
                excessRewardAmount
            )
        );
        vm.prank(manager);
        flywheel.allocate(limitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when campaign has insufficient funds for allocation
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param excessiveAllocation Allocation amount that exceeds campaign balance
    function test_revert_insufficientFunds(uint120 paymentAmount, uint120 excessiveAllocation) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        excessiveAllocation = uint120(bound(excessiveAllocation, EXCESSIVE_MIN_REWARD, type(uint120).max));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        authorizePayment(paymentInfo);

        bytes memory hookData = createCashbackHookData(paymentInfo, excessiveAllocation);

        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully allocates funds for single payment
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate for the payment
    function test_success_singleAllocation(uint120 paymentAmount, uint120 allocateAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        authorizePayment(paymentInfo);

        CashbackRewards.RewardState memory rewardsBefore = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);

        bytes memory hookData = createCashbackHookData(paymentInfo, allocateAmount);

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutAllocated(
            unlimitedCashbackCampaign,
            address(usdc),
            bytes32(bytes20(buyer)),
            allocateAmount,
            abi.encodePacked(paymentInfoHash)
        );

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);

        CashbackRewards.RewardState memory rewardsAfter = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(rewardsAfter.allocated, rewardsBefore.allocated + allocateAmount);
        assertEq(rewardsAfter.distributed, rewardsBefore.distributed); // Should remain unchanged
    }

    /// @dev Successfully allocates maximum campaign balance
    function test_success_maxCampaignBalance() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, DEFAULT_CAMPAIGN_BALANCE);
        uint120 maxAllocation = DEFAULT_CAMPAIGN_BALANCE;

        authorizePayment(paymentInfo);

        bytes memory hookData = createCashbackHookData(paymentInfo, maxAllocation);

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);

        CashbackRewards.RewardState memory rewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(rewards.allocated, maxAllocation);
    }

    /// @dev Successfully processes batch allocations for multiple payments
    /// @param firstPaymentAmount Payment amount in USDC for first transaction
    /// @param secondPaymentAmount Payment amount in USDC for second transaction
    /// @param firstAllocation Allocation amount for first payment
    /// @param secondAllocation Allocation amount for second payment
    function test_success_batchAllocateMultiplePayments(
        uint120 firstPaymentAmount,
        uint120 secondPaymentAmount,
        uint120 firstAllocation,
        uint120 secondAllocation
    ) public {
        // Use reasonable bounds to ensure buyer can afford both payments and campaign can afford both allocations
        firstPaymentAmount = uint120(bound(firstPaymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT / 2));
        secondPaymentAmount = uint120(bound(secondPaymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT / 2));
        firstAllocation = uint120(bound(firstAllocation, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));
        secondAllocation = uint120(bound(secondAllocation, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));

        // Create two different payments
        AuthCaptureEscrow.PaymentInfo memory firstPayment = createPaymentInfo(buyer, firstPaymentAmount);
        firstPayment.salt = uint256(keccak256("first_payment"));

        AuthCaptureEscrow.PaymentInfo memory secondPayment = createPaymentInfo(buyer, secondPaymentAmount);
        secondPayment.salt = uint256(keccak256("second_payment"));

        // Authorize both payments
        authorizePayment(firstPayment);
        authorizePayment(secondPayment);

        // Create batch hook data with multiple payouts
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](2);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: firstPayment, payoutAmount: firstAllocation});
        paymentRewards[1] = CashbackRewards.PaymentReward({paymentInfo: secondPayment, payoutAmount: secondAllocation});
        bytes memory batchHookData = abi.encode(paymentRewards, true);

        // Get initial states
        CashbackRewards.RewardState memory firstRewardsBefore = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsBefore =
            getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        // Execute batch allocation
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), batchHookData);

        // Verify both allocations were processed
        CashbackRewards.RewardState memory firstRewardsAfter = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsAfter = getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        assertEq(firstRewardsAfter.allocated, firstRewardsBefore.allocated + firstAllocation);
        assertEq(secondRewardsAfter.allocated, secondRewardsBefore.allocated + secondAllocation);
        assertEq(firstRewardsAfter.distributed, firstRewardsBefore.distributed);
        assertEq(secondRewardsAfter.distributed, secondRewardsBefore.distributed);
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Verifies RewardFailed event is emitted when attempting to allocate zero amount with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_edge_emitsRewardFailed_onZeroAmount_whenRevertOnErrorFalse(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, 0);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        authorizePayment(paymentInfo);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            0,
            CashbackRewards.RewardOperation.ALLOCATE,
            abi.encodeWithSelector(CashbackRewards.ZeroPayoutAmount.selector)
        );

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when payment token differs from campaign token with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Allocation amount to attempt
    /// @param wrongToken Incorrect token address used in payment
    function test_edge_emitsRewardFailed_onWrongToken_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount,
        address wrongToken
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        paymentInfo.token = wrongToken; // Wrong token

        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, allocateAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            allocateAmount,
            CashbackRewards.RewardOperation.ALLOCATE,
            abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector)
        );

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when attempting to allocate for uncollected payment with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Allocation amount to attempt
    function test_edge_emitsRewardFailed_onPaymentNotCollected_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, allocateAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Don't authorize the payment - leave it uncollected

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            allocateAmount,
            CashbackRewards.RewardOperation.ALLOCATE,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies mixed batch processing handles valid and invalid allocations correctly with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for both transactions
    /// @param allocateAmount Allocation amount to attempt for both payments
    function test_edge_mixedPayments_someValidSomeInvalid_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        // Create valid payment (authorized)
        AuthCaptureEscrow.PaymentInfo memory validPayment = createPaymentInfo(buyer, paymentAmount);
        validPayment.salt = uint256(keccak256("valid"));
        authorizePayment(validPayment);

        // Create invalid payment (not authorized)
        AuthCaptureEscrow.PaymentInfo memory invalidPayment = createPaymentInfo(buyer, paymentAmount);
        invalidPayment.salt = uint256(keccak256("invalid"));

        bytes memory hookData =
            createMixedCashbackHookDataNoRevert(validPayment, allocateAmount, invalidPayment, allocateAmount);
        bytes32 invalidPaymentHash = escrow.getHash(invalidPayment);

        // Expect event for the invalid payment
        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            invalidPaymentHash,
            allocateAmount,
            CashbackRewards.RewardOperation.ALLOCATE,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        // Should not revert, but process the valid payment and emit event for invalid
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);

        // Verify the valid payment was processed
        CashbackRewards.RewardState memory validRewards = getRewardsInfo(validPayment, unlimitedCashbackCampaign);
        assertEq(validRewards.allocated, allocateAmount);

        // Verify the invalid payment was not processed
        CashbackRewards.RewardState memory invalidRewards = getRewardsInfo(invalidPayment, unlimitedCashbackCampaign);
        assertEq(invalidRewards.allocated, 0);
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies correct Flywheel event emission for successful allocation
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate for the payment
    function test_onAllocate_emitsFlywheelEvents(uint120 paymentAmount, uint120 allocateAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, allocateAmount);

        authorizePayment(paymentInfo);

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutAllocated(
            unlimitedCashbackCampaign,
            address(usdc),
            bytes32(bytes20(buyer)),
            allocateAmount,
            abi.encodePacked(paymentInfoHash)
        );

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }
}
