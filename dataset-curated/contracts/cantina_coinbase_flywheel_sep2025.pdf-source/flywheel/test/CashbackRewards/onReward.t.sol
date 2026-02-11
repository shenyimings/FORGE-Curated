// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {CashbackRewardsBase} from "./CashbackRewardsBase.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {Flywheel} from "../../src/Flywheel.sol";
import {CashbackRewards} from "../../src/hooks/CashbackRewards.sol";
import {SimpleRewards} from "../../src/hooks/SimpleRewards.sol";

contract OnRewardTest is CashbackRewardsBase {
    function test_revertsOnUnauthorizedCaller(uint120 paymentAmount, uint120 rewardAmount, address unauthorizedCaller)
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

    function test_revertsOnZeroAmount(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, 0);

        chargePayment(paymentInfo);

        vm.expectRevert(CashbackRewards.ZeroPayoutAmount.selector);
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    function test_revertsOnWrongToken(uint120 paymentAmount, uint120 rewardAmount, address wrongToken) public {
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

    function test_revertsOnUnauthorizedPayment(uint120 paymentAmount, uint120 rewardAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        rewardAmount = uint120(bound(rewardAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, rewardAmount);

        vm.expectRevert(CashbackRewards.PaymentNotCollected.selector);
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    function test_revertsOnInsufficientFunds(uint120 paymentAmount, uint120 excessiveReward) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        excessiveReward = uint120(bound(excessiveReward, EXCESSIVE_MIN_REWARD, type(uint120).max));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, excessiveReward);

        chargePayment(paymentInfo);

        vm.expectRevert();
        vm.prank(manager);
        flywheel.send(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    function test_revertsOnMaxRewardPercentageExceeded() public {
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

    function test_successfulReward(uint120 paymentAmount, uint120 rewardAmount) public {
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

    function test_successfulRewardWithinMaxPercentage(uint120 paymentAmount, uint120 rewardAmount) public {
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

    function test_rewardAfterExistingAllocation(uint120 paymentAmount, uint120 allocateAmount, uint120 rewardAmount)
        public
    {
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

    function test_rewardAfterExistingDistribution(
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

    function test_cumulativeRewardPercentageValidation() public {
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

    function test_batchRewardMultiplePayments(
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

    function test_emitsFlywheelEvents() public {
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
