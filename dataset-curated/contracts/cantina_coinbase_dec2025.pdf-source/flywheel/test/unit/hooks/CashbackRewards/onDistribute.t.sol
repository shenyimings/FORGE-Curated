// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

import {CashbackRewardsTest} from "../../../lib/CashbackRewardsTest.sol";

import {Flywheel} from "../../../../src/Flywheel.sol";
import {CashbackRewards} from "../../../../src/hooks/CashbackRewards.sol";
import {SimpleRewards} from "../../../../src/hooks/SimpleRewards.sol";

contract OnDistributeTest is CashbackRewardsTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not authorized manager
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Amount to distribute for the payment
    /// @param unauthorizedCaller Address that is not the campaign manager
    function test_revert_unauthorizedCaller(
        uint120 paymentAmount,
        uint120 distributeAmount,
        address unauthorizedCaller
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(unauthorizedCaller != manager && unauthorizedCaller != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, distributeAmount);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(unauthorizedCaller);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to distribute zero amount
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_revert_zeroAmount(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, 0);

        chargePayment(paymentInfo);

        vm.expectRevert(CashbackRewards.ZeroPayoutAmount.selector);
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when payment token differs from campaign token
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Amount to distribute for the payment
    /// @param wrongToken Incorrect token address used in payment
    function test_revert_wrongToken(uint120 paymentAmount, uint120 distributeAmount, address wrongToken) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        paymentInfo.token = wrongToken;

        bytes memory hookData = createCashbackHookData(paymentInfo, distributeAmount);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector));
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to distribute for payment that hasn't been collected
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Amount to distribute for the payment
    function test_revert_unauthorizedPayment(uint120 paymentAmount, uint120 distributeAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, distributeAmount);

        vm.expectRevert(CashbackRewards.PaymentNotCollected.selector);
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to distribute more than allocated amount
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Amount to distribute (exceeds allocation)
    function test_revert_insufficientAllocation(uint120 paymentAmount, uint120 distributeAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, distributeAmount);

        chargePayment(paymentInfo);

        vm.expectRevert(abi.encodeWithSelector(CashbackRewards.InsufficientAllocation.selector, distributeAmount, 0));
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully distributes allocated funds to recipient
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Amount to distribute
    function test_success_singleDistribution(uint120 paymentAmount, uint120 distributeAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, distributeAmount);
        bytes memory distributeHookData = createCashbackHookData(paymentInfo, distributeAmount);

        chargePayment(paymentInfo);

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        CashbackRewards.RewardState memory rewardsBefore = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);

        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), distributeHookData);

        CashbackRewards.RewardState memory rewardsAfter = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);

        assertEq(rewardsAfter.allocated, rewardsBefore.allocated - distributeAmount);
        assertEq(rewardsAfter.distributed, rewardsBefore.distributed + distributeAmount);
    }

    /// @dev Successfully distributes within maximum percentage limit
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Amount to distribute within percentage limit
    function test_success_distributeWithinMaxPercentage(uint120 paymentAmount, uint120 distributeAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        uint120 maxValidDistribute = uint120(
            (uint256(paymentAmount) * uint256(TEST_MAX_REWARD_BASIS_POINTS)) / uint256(MAX_REWARD_BASIS_POINTS_DIVISOR)
        );
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, maxValidDistribute));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, distributeAmount);
        bytes memory distributeHookData = createCashbackHookData(paymentInfo, distributeAmount);

        usdc.mint(limitedCashbackCampaign, maxValidDistribute);
        chargePayment(paymentInfo);

        vm.prank(manager);
        flywheel.allocate(limitedCashbackCampaign, address(usdc), allocateHookData);

        vm.prank(manager);
        flywheel.distribute(limitedCashbackCampaign, address(usdc), distributeHookData);

        CashbackRewards.RewardState memory rewards = getRewardsInfo(paymentInfo, limitedCashbackCampaign);
        assertEq(rewards.distributed, distributeAmount);
    }

    /// @dev Successfully distributes partial amount from allocated funds
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocationAmount Amount to allocate initially
    /// @param distributionAmount Amount to distribute (partial)
    function test_success_partialDistribution(
        uint120 paymentAmount,
        uint120 allocationAmount,
        uint120 distributionAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocationAmount = uint120(bound(allocationAmount, MIN_ALLOCATION_AMOUNT, MAX_ALLOCATION_AMOUNT));
        distributionAmount = uint120(bound(distributionAmount, MIN_REWARD_AMOUNT, allocationAmount));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocationAmount);
        bytes memory distributeHookData = createCashbackHookData(paymentInfo, distributionAmount);

        chargePayment(paymentInfo);

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), distributeHookData);

        CashbackRewards.RewardState memory rewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(rewards.allocated, allocationAmount - distributionAmount);
        assertEq(rewards.distributed, distributionAmount);
    }

    /// @dev Successfully processes multiple distributions for same payment
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocationAmount Amount to allocate initially
    /// @param firstDistribution Amount for first distribution
    /// @param secondDistribution Amount for second distribution
    function test_success_multipleDistributions(
        uint120 paymentAmount,
        uint120 allocationAmount,
        uint120 firstDistribution,
        uint120 secondDistribution
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocationAmount = uint120(bound(allocationAmount, MIN_ALLOCATION_AMOUNT, MAX_ALLOCATION_AMOUNT));
        firstDistribution = uint120(bound(firstDistribution, MIN_REWARD_AMOUNT, allocationAmount / 2));
        secondDistribution = uint120(bound(secondDistribution, MIN_REWARD_AMOUNT, allocationAmount - firstDistribution));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocationAmount);

        chargePayment(paymentInfo);

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        bytes memory firstDistributeHookData = createCashbackHookData(paymentInfo, firstDistribution);
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), firstDistributeHookData);

        bytes memory secondDistributeHookData = createCashbackHookData(paymentInfo, secondDistribution);
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), secondDistributeHookData);

        CashbackRewards.RewardState memory rewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(rewards.allocated, allocationAmount - firstDistribution - secondDistribution);
        assertEq(rewards.distributed, firstDistribution + secondDistribution);
    }

    /// @dev Successfully processes batch distributions for multiple payments
    /// @param firstPaymentAmount Payment amount in USDC for first transaction
    /// @param secondPaymentAmount Payment amount in USDC for second transaction
    /// @param firstAllocation Allocation amount for first payment
    /// @param secondAllocation Allocation amount for second payment
    /// @param firstDistribute Distribution amount for first payment
    /// @param secondDistribute Distribution amount for second payment
    function test_success_batchDistributeMultiplePayments(
        uint120 firstPaymentAmount,
        uint120 secondPaymentAmount,
        uint120 firstAllocation,
        uint120 secondAllocation,
        uint120 firstDistribute,
        uint120 secondDistribute
    ) public {
        // Use reasonable bounds to ensure buyer can afford both payments
        firstPaymentAmount = uint120(bound(firstPaymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        secondPaymentAmount = uint120(bound(secondPaymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        firstAllocation = uint120(bound(firstAllocation, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));
        secondAllocation = uint120(bound(secondAllocation, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));
        firstDistribute = uint120(bound(firstDistribute, MIN_REWARD_AMOUNT, firstAllocation));
        secondDistribute = uint120(bound(secondDistribute, MIN_REWARD_AMOUNT, secondAllocation));

        // Create two different payments
        AuthCaptureEscrow.PaymentInfo memory firstPayment = createPaymentInfo(buyer, firstPaymentAmount);
        firstPayment.salt = uint256(keccak256("first_payment"));

        AuthCaptureEscrow.PaymentInfo memory secondPayment = createPaymentInfo(buyer, secondPaymentAmount);
        secondPayment.salt = uint256(keccak256("second_payment"));

        // Charge both payments and allocate rewards
        chargePayment(firstPayment);
        chargePayment(secondPayment);

        // Allocate rewards for both payments
        bytes memory firstAllocateData = createCashbackHookData(firstPayment, firstAllocation);
        bytes memory secondAllocateData = createCashbackHookData(secondPayment, secondAllocation);

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), firstAllocateData);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), secondAllocateData);

        // Create batch distribution hook data
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](2);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: firstPayment, payoutAmount: firstDistribute});
        paymentRewards[1] = CashbackRewards.PaymentReward({paymentInfo: secondPayment, payoutAmount: secondDistribute});
        bytes memory batchHookData = abi.encode(paymentRewards, true);

        // Get initial states
        CashbackRewards.RewardState memory firstRewardsBefore = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsBefore =
            getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        // Execute batch distribution
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), batchHookData);

        // Verify both distributions were processed
        CashbackRewards.RewardState memory firstRewardsAfter = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsAfter = getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        assertEq(firstRewardsAfter.allocated, firstRewardsBefore.allocated - firstDistribute);
        assertEq(firstRewardsAfter.distributed, firstRewardsBefore.distributed + firstDistribute);
        assertEq(secondRewardsAfter.allocated, secondRewardsBefore.allocated - secondDistribute);
        assertEq(secondRewardsAfter.distributed, secondRewardsBefore.distributed + secondDistribute);
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Verifies RewardFailed event is emitted when attempting to distribute zero amount with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Allocation amount to set up for distribution
    function test_edge_emitsRewardFailed_onZeroAmount_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // First allocate some funds
        chargePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        // Try to distribute zero amount with revertOnError = false
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, 0);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            0,
            CashbackRewards.RewardOperation.DISTRIBUTE,
            abi.encodeWithSelector(CashbackRewards.ZeroPayoutAmount.selector)
        );

        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when payment token differs from campaign token with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Allocation amount to set up for distribution
    /// @param distributeAmount Distribution amount to attempt
    /// @param wrongToken Incorrect token address used in payment
    function test_edge_emitsRewardFailed_onWrongToken_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount,
        uint120 distributeAmount,
        address wrongToken
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, allocateAmount));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        // First allocate some funds
        chargePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        // Change token for distribute
        paymentInfo.token = wrongToken; // Wrong token
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, distributeAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            distributeAmount,
            CashbackRewards.RewardOperation.DISTRIBUTE,
            abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector)
        );

        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when attempting to distribute for uncollected payment with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Distribution amount to attempt
    function test_edge_emitsRewardFailed_onPaymentNotCollected_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 distributeAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, distributeAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Don't charge the payment - leave it uncollected

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            distributeAmount,
            CashbackRewards.RewardOperation.DISTRIBUTE,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies mixed batch processing handles valid and invalid distributions correctly with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for both transactions
    /// @param allocateAmount Allocation amount to set up for distribution
    /// @param distributeAmount Distribution amount to attempt
    function test_edge_mixedPayments_someValidSomeInvalid_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount,
        uint120 distributeAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, allocateAmount));

        // Create valid payment (charged and allocated)
        AuthCaptureEscrow.PaymentInfo memory validPayment = createPaymentInfo(buyer, paymentAmount);
        validPayment.salt = uint256(keccak256("valid"));
        chargePayment(validPayment);
        bytes memory allocateHookData = createCashbackHookData(validPayment, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        // Create invalid payment (not charged)
        AuthCaptureEscrow.PaymentInfo memory invalidPayment = createPaymentInfo(buyer, paymentAmount);
        invalidPayment.salt = uint256(keccak256("invalid"));

        bytes memory hookData =
            createMixedCashbackHookDataNoRevert(validPayment, distributeAmount, invalidPayment, distributeAmount);
        bytes32 invalidPaymentHash = escrow.getHash(invalidPayment);

        // Expect event for the invalid payment
        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            invalidPaymentHash,
            distributeAmount,
            CashbackRewards.RewardOperation.DISTRIBUTE,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        // Should not revert, but process the valid payment and emit event for invalid
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), hookData);

        // Verify the valid payment was processed
        CashbackRewards.RewardState memory validRewards = getRewardsInfo(validPayment, unlimitedCashbackCampaign);
        assertEq(validRewards.allocated, allocateAmount - distributeAmount);
        assertEq(validRewards.distributed, distributeAmount);

        // Verify the invalid payment was not processed
        CashbackRewards.RewardState memory invalidRewards = getRewardsInfo(invalidPayment, unlimitedCashbackCampaign);
        assertEq(invalidRewards.allocated, 0);
        assertEq(invalidRewards.distributed, 0);
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies correct Flywheel event emission for successful distribution
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param distributeAmount Amount to distribute
    function test_onDistribute_emitsFlywheelEvents(uint120 paymentAmount, uint120 distributeAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, distributeAmount);
        bytes memory distributeHookData = createCashbackHookData(paymentInfo, distributeAmount);

        chargePayment(paymentInfo);

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutDistributed(
            unlimitedCashbackCampaign,
            address(usdc),
            bytes32(bytes20(buyer)),
            buyer,
            distributeAmount,
            abi.encodePacked(paymentInfoHash)
        );

        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), distributeHookData);
    }
}
