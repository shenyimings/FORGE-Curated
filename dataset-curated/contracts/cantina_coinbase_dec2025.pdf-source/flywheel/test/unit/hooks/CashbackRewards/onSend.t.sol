// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

import {CashbackRewardsTest} from "../../../lib/CashbackRewardsTest.sol";

import {Flywheel} from "../../../../src/Flywheel.sol";
import {CashbackRewards} from "../../../../src/hooks/CashbackRewards.sol";
import {SimpleRewards} from "../../../../src/hooks/SimpleRewards.sol";

contract OnRewardTest is CashbackRewardsTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not authorized manager
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param rewardAmount Reward amount to attempt
    /// @param unauthorizedCaller Address that is not the campaign manager
    function test_revert_unauthorizedCaller(uint120 paymentAmount, uint120 rewardAmount, address unauthorizedCaller)
        public
    {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(unauthorizedCaller != manager && unauthorizedCaller != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, rewardAmount);

        chargePayment(paymentInfo);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(unauthorizedCaller);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to reward zero amount
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_revert_zeroAmount(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, 0);

        chargePayment(paymentInfo);

        vm.expectRevert(CashbackRewards.ZeroPayoutAmount.selector);
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when payment token differs from campaign token
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param rewardAmount Reward amount to attempt
    /// @param wrongToken Incorrect token address used in payment
    function test_revert_wrongToken(uint120 paymentAmount, uint120 rewardAmount, address wrongToken) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        paymentInfo.token = wrongToken;

        bytes memory hookData = createCashbackHookData(paymentInfo, rewardAmount);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector));
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to reward payment that hasn't been collected
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param rewardAmount Reward amount to attempt
    function test_revert_unauthorizedPayment(uint120 paymentAmount, uint120 rewardAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, rewardAmount);

        vm.expectRevert(CashbackRewards.PaymentNotCollected.selector);
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when campaign has insufficient funds for reward
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param excessiveReward Reward amount that exceeds campaign balance
    function test_revert_insufficientFunds(uint120 paymentAmount, uint120 excessiveReward) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        excessiveReward = uint120(bound(excessiveReward, EXCESSIVE_MIN_REWARD, type(uint120).max));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, excessiveReward);

        chargePayment(paymentInfo);

        vm.expectRevert();
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when reward exceeds maximum percentage limit for campaign
    function test_revert_maxRewardPercentageExceeded() public {
        // Use hardcoded values to make the percentage test crystal clear
        uint120 paymentAmount = 1000e6; // 1000 USDC payment
        uint120 excessRewardAmount = paymentAmount / 1000; // 0.1% of payment
        uint120 excessiveReward = paymentAmount / 100 + excessRewardAmount; // 1.1% > 1% limit

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        bytes memory hookData = createCashbackHookData(paymentInfo, excessiveReward);

        chargePayment(paymentInfo);

        uint120 maxAllowedAmount = (paymentAmount * TEST_MAX_REWARD_BASIS_POINTS) / MAX_REWARD_BASIS_POINTS_DIVISOR; // 10 USDC (1%)
        vm.expectRevert(
            abi.encodeWithSelector(
                CashbackRewards.RewardExceedsMaxPercentage.selector,
                paymentInfoHash,
                maxAllowedAmount,
                excessRewardAmount
            )
        );
        vm.prank(manager);
        flywheel.send(limitedCashbackCampaign, address(usdc), hookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully processes single payment reward
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param rewardAmount Reward amount to distribute
    function test_success_singleReward(uint120 paymentAmount, uint120 rewardAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, rewardAmount);

        chargePayment(paymentInfo);

        CashbackRewards.RewardState memory rewardsBefore = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);

        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);

        CashbackRewards.RewardState memory rewardsAfter = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);

        assertEq(rewardsAfter.allocated, rewardsBefore.allocated);
        assertEq(rewardsAfter.distributed, rewardsBefore.distributed + rewardAmount);
    }

    /// @dev Successfully processes reward within maximum percentage limit
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param rewardAmount Reward amount within percentage limit
    function test_success_rewardWithinMaxPercentage(uint120 paymentAmount, uint120 rewardAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        uint120 maxValidReward = uint120(
            (uint256(paymentAmount) * uint256(TEST_MAX_REWARD_BASIS_POINTS)) / uint256(MAX_REWARD_BASIS_POINTS_DIVISOR)
        );
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, maxValidReward));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, rewardAmount);
        usdc.mint(limitedCashbackCampaign, maxValidReward);
        chargePayment(paymentInfo);

        vm.prank(manager);
        flywheel.send(limitedCashbackCampaign, address(usdc), hookData);

        CashbackRewards.RewardState memory rewards = getRewardsInfo(paymentInfo, limitedCashbackCampaign);
        assertEq(rewards.distributed, rewardAmount);
    }

    /// @dev Successfully processes reward after existing allocation for different payment
    /// @param paymentAmount Payment amount in USDC for both transactions
    /// @param allocateAmount Amount to allocate for first payment
    /// @param rewardAmount Amount to reward for second payment
    function test_success_rewardAfterExistingAllocation(
        uint120 paymentAmount,
        uint120 allocateAmount,
        uint120 rewardAmount
    ) public {
        // Use reasonable bounds to ensure buyer can afford both payments
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));

        AuthCaptureEscrow.PaymentInfo memory allocationPaymentInfo = createPaymentInfo(buyer, paymentAmount);
        allocationPaymentInfo.salt = uint256(keccak256("allocation"));

        AuthCaptureEscrow.PaymentInfo memory rewardPaymentInfo = createPaymentInfo(buyer, paymentAmount);
        rewardPaymentInfo.salt = uint256(keccak256("reward"));

        authorizePayment(allocationPaymentInfo);
        bytes memory allocateHookData = createCashbackHookData(allocationPaymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        chargePayment(rewardPaymentInfo);
        bytes memory rewardHookData = createCashbackHookData(rewardPaymentInfo, rewardAmount);
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), rewardHookData);

        CashbackRewards.RewardState memory allocationRewards =
            getRewardsInfo(allocationPaymentInfo, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory rewardRewards = getRewardsInfo(rewardPaymentInfo, unlimitedCashbackCampaign);

        assertEq(allocationRewards.allocated, allocateAmount);
        assertEq(allocationRewards.distributed, 0);
        assertEq(rewardRewards.allocated, 0);
        assertEq(rewardRewards.distributed, rewardAmount);
    }

    /// @dev Successfully processes reward after existing distribution for different payment
    /// @param paymentAmount Payment amount in USDC for both transactions
    /// @param allocateAmount Amount to allocate for first payment
    /// @param distributeAmount Amount to distribute for first payment
    /// @param rewardAmount Amount to reward for second payment
    function test_success_rewardAfterExistingDistribution(
        uint120 paymentAmount,
        uint120 allocateAmount,
        uint120 distributeAmount,
        uint120 rewardAmount
    ) public {
        // Use reasonable bounds to ensure buyer can afford both payments
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        allocateAmount = uint120(bound(allocateAmount, MIN_ALLOCATION_AMOUNT, MAX_ALLOCATION_AMOUNT / 2));
        distributeAmount = uint120(bound(distributeAmount, MIN_REWARD_AMOUNT, allocateAmount));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));

        AuthCaptureEscrow.PaymentInfo memory distributionPaymentInfo = createPaymentInfo(buyer, paymentAmount);
        distributionPaymentInfo.salt = uint256(keccak256("distribution"));

        AuthCaptureEscrow.PaymentInfo memory rewardPaymentInfo = createPaymentInfo(buyer, paymentAmount);
        rewardPaymentInfo.salt = uint256(keccak256("reward"));

        chargePayment(distributionPaymentInfo);
        bytes memory allocateHookData = createCashbackHookData(distributionPaymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        bytes memory distributeHookData = createCashbackHookData(distributionPaymentInfo, distributeAmount);
        vm.prank(manager);
        flywheel.distribute(unlimitedCashbackCampaign, address(usdc), distributeHookData);

        chargePayment(rewardPaymentInfo);
        bytes memory rewardHookData = createCashbackHookData(rewardPaymentInfo, rewardAmount);
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), rewardHookData);

        CashbackRewards.RewardState memory distributionRewards =
            getRewardsInfo(distributionPaymentInfo, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory rewardRewards = getRewardsInfo(rewardPaymentInfo, unlimitedCashbackCampaign);

        assertEq(distributionRewards.allocated, allocateAmount - distributeAmount);
        assertEq(distributionRewards.distributed, distributeAmount);
        assertEq(rewardRewards.allocated, 0);
        assertEq(rewardRewards.distributed, rewardAmount);
    }

    /// @dev Successfully processes multiple rewards for same payment within cumulative percentage limit
    function test_success_cumulativeRewardPercentageValidation() public {
        uint120 paymentAmount = 1000e6; // 1000 USDC payment
        uint120 firstReward = 5e6; // 5 USDC (0.5%)
        uint120 secondReward = 5e6; // 5 USDC (0.5%) - total now 1.0%
        uint120 thirdReward = 1e6; // 1 USDC (0.1%) - would make total 1.1% > 1% limit

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        chargePayment(paymentInfo);

        bytes memory firstRewardHookData = createCashbackHookData(paymentInfo, firstReward);
        vm.prank(manager);
        flywheel.send(limitedCashbackCampaign, address(usdc), firstRewardHookData);

        bytes memory secondRewardHookData = createCashbackHookData(paymentInfo, secondReward);
        vm.prank(manager);
        flywheel.send(limitedCashbackCampaign, address(usdc), secondRewardHookData);

        uint120 maxAllowedAmount = (paymentAmount * TEST_MAX_REWARD_BASIS_POINTS) / MAX_REWARD_BASIS_POINTS_DIVISOR;

        bytes memory thirdRewardHookData = createCashbackHookData(paymentInfo, thirdReward);
        vm.expectRevert(
            abi.encodeWithSelector(
                CashbackRewards.RewardExceedsMaxPercentage.selector, paymentInfoHash, maxAllowedAmount, thirdReward
            )
        );
        vm.prank(manager);
        flywheel.send(limitedCashbackCampaign, address(usdc), thirdRewardHookData);
    }

    /// @dev Successfully processes batch rewards for multiple payments
    /// @param firstPaymentAmount Payment amount in USDC for first transaction
    /// @param secondPaymentAmount Payment amount in USDC for second transaction
    /// @param firstReward Reward amount for first payment
    /// @param secondReward Reward amount for second payment
    function test_success_batchRewardMultiplePayments(
        uint120 firstPaymentAmount,
        uint120 secondPaymentAmount,
        uint120 firstReward,
        uint120 secondReward
    ) public {
        // Use reasonable bounds to ensure buyer can afford both payments
        firstPaymentAmount = uint120(bound(firstPaymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        secondPaymentAmount = uint120(bound(secondPaymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        firstReward = uint120(bound(firstReward, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));
        secondReward = uint120(bound(secondReward, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));

        // Create two different payments
        AuthCaptureEscrow.PaymentInfo memory firstPayment = createPaymentInfo(buyer, firstPaymentAmount);
        firstPayment.salt = uint256(keccak256("first_payment"));

        AuthCaptureEscrow.PaymentInfo memory secondPayment = createPaymentInfo(buyer, secondPaymentAmount);
        secondPayment.salt = uint256(keccak256("second_payment"));

        // Charge both payments
        chargePayment(firstPayment);
        chargePayment(secondPayment);

        // Create batch reward hook data
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](2);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: firstPayment, payoutAmount: firstReward});
        paymentRewards[1] = CashbackRewards.PaymentReward({paymentInfo: secondPayment, payoutAmount: secondReward});
        bytes memory batchHookData = abi.encode(paymentRewards, true);

        // Get initial states
        CashbackRewards.RewardState memory firstRewardsBefore = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsBefore =
            getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        // Execute batch reward
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), batchHookData);

        // Verify both rewards were processed
        CashbackRewards.RewardState memory firstRewardsAfter = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsAfter = getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        assertEq(firstRewardsAfter.allocated, firstRewardsBefore.allocated);
        assertEq(firstRewardsAfter.distributed, firstRewardsBefore.distributed + firstReward);
        assertEq(secondRewardsAfter.allocated, secondRewardsBefore.allocated);
        assertEq(secondRewardsAfter.distributed, secondRewardsBefore.distributed + secondReward);
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Verifies RewardFailed event is emitted when attempting to reward zero amount with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_edge_emitsRewardFailed_onZeroAmount_whenRevertOnErrorFalse(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, 0);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        chargePayment(paymentInfo);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            0,
            CashbackRewards.RewardOperation.SEND,
            abi.encodeWithSelector(CashbackRewards.ZeroPayoutAmount.selector)
        );

        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when payment token differs from campaign token with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param rewardAmount Reward amount to attempt distribution
    /// @param wrongToken Incorrect token address used in payment
    function test_edge_emitsRewardFailed_onWrongToken_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 rewardAmount,
        address wrongToken
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        paymentInfo.token = wrongToken; // Wrong token

        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, rewardAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            rewardAmount,
            CashbackRewards.RewardOperation.SEND,
            abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector)
        );

        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when attempting to reward uncollected payment with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param rewardAmount Reward amount to attempt distribution
    function test_edge_emitsRewardFailed_onPaymentNotCollected_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 rewardAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, rewardAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Don't charge the payment - leave it uncollected

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            rewardAmount,
            CashbackRewards.RewardOperation.SEND,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when reward exceeds max percentage limit with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction (bounded to avoid overflow)
    function test_edge_emitsRewardFailed_onMaxPercentageExceeded_whenRevertOnErrorFalse(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC to avoid overflow

        // Calculate max allowed amount (1% of payment)
        uint120 maxAllowedAmount = (paymentAmount * TEST_MAX_REWARD_BASIS_POINTS) / MAX_REWARD_BASIS_POINTS_DIVISOR;

        // Skip test if maxAllowedAmount would be 0 (payment too small)
        vm.assume(maxAllowedAmount > 0);

        uint120 excessRewardAmount = 1;
        uint120 excessiveReward = maxAllowedAmount + excessRewardAmount; // Just over the limit

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, excessiveReward);

        chargePayment(paymentInfo);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            excessiveReward,
            CashbackRewards.RewardOperation.SEND,
            abi.encodeWithSelector(
                CashbackRewards.RewardExceedsMaxPercentage.selector,
                paymentInfoHash,
                maxAllowedAmount,
                excessRewardAmount
            )
        );

        vm.prank(manager);
        flywheel.send(limitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies mixed batch processing handles valid and invalid payments correctly with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for both transactions
    /// @param rewardAmount Reward amount to attempt distribution
    function test_edge_mixedPayments_someValidSomeInvalid_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 rewardAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        // Create valid payment (charged)
        AuthCaptureEscrow.PaymentInfo memory validPayment = createPaymentInfo(buyer, paymentAmount);
        validPayment.salt = uint256(keccak256("valid"));
        chargePayment(validPayment);

        // Create invalid payment (not charged)
        AuthCaptureEscrow.PaymentInfo memory invalidPayment = createPaymentInfo(buyer, paymentAmount);
        invalidPayment.salt = uint256(keccak256("invalid"));

        bytes memory hookData =
            createMixedCashbackHookDataNoRevert(validPayment, rewardAmount, invalidPayment, rewardAmount);
        bytes32 invalidPaymentHash = escrow.getHash(invalidPayment);

        // Expect event for the invalid payment
        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            invalidPaymentHash,
            rewardAmount,
            CashbackRewards.RewardOperation.SEND,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        // Should not revert, but process the valid payment and emit event for invalid
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);

        // Verify the valid payment was processed
        CashbackRewards.RewardState memory validRewards = getRewardsInfo(validPayment, unlimitedCashbackCampaign);
        assertEq(validRewards.distributed, rewardAmount);

        // Verify the invalid payment was not processed
        CashbackRewards.RewardState memory invalidRewards = getRewardsInfo(invalidPayment, unlimitedCashbackCampaign);
        assertEq(invalidRewards.distributed, 0);
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies correct Flywheel event emission for successful reward
    function test_onSend_emitsFlywheelEvents() public {
        uint120 paymentAmount = 1000e6;
        uint120 rewardAmount = 100e6;

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, rewardAmount);

        chargePayment(paymentInfo);

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutSent(
            unlimitedCashbackCampaign, address(usdc), buyer, rewardAmount, abi.encodePacked(paymentInfoHash)
        );

        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }
}
