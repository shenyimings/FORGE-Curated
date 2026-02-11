// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

import {CashbackRewardsTest} from "../../../lib/CashbackRewardsTest.sol";

import {Flywheel} from "../../../../src/Flywheel.sol";
import {CashbackRewards} from "../../../../src/hooks/CashbackRewards.sol";
import {SimpleRewards} from "../../../../src/hooks/SimpleRewards.sol";

contract OnDeallocateTest is CashbackRewardsTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not authorized manager
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param deallocateAmount Amount to deallocate for the payment
    /// @param unauthorizedCaller Address that is not the campaign manager
    function test_revert_unauthorizedCaller(
        uint120 paymentAmount,
        uint120 deallocateAmount,
        address unauthorizedCaller
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(unauthorizedCaller != manager && unauthorizedCaller != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, deallocateAmount);

        authorizePayment(paymentInfo);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), hookData);

        vm.prank(unauthorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(SimpleRewards.Unauthorized.selector));
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to deallocate zero amount
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_revert_zeroAmount(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        authorizePayment(paymentInfo);

        bytes memory hookData = createCashbackHookData(paymentInfo, 0);

        vm.expectRevert(CashbackRewards.ZeroPayoutAmount.selector);
        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when payment token differs from campaign token
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param deallocateAmount Amount to deallocate for the payment
    /// @param wrongToken Incorrect token address used in payment
    function test_revert_wrongToken(uint120 paymentAmount, uint120 deallocateAmount, address wrongToken) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        paymentInfo.token = wrongToken;

        bytes memory hookData = createCashbackHookData(paymentInfo, deallocateAmount);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector));
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to deallocate for payment that hasn't been collected
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param deallocateAmount Amount to deallocate for the payment
    function test_revert_unauthorizedPayment(uint120 paymentAmount, uint120 deallocateAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookData(paymentInfo, deallocateAmount);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector));
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when attempting to deallocate more than allocated amount
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_revert_insufficientAllocation(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        uint120 allocateAmount = 100e6;
        uint120 excessiveDeallocate = 200e6;

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        authorizePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        bytes memory deallocateHookData = createCashbackHookData(paymentInfo, excessiveDeallocate);
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(CashbackRewards.InsufficientAllocation.selector, excessiveDeallocate, allocateAmount)
        );
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), deallocateHookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully deallocates partial amount from allocated funds
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate initially
    /// @param deallocateAmount Amount to deallocate (partial)
    function test_success_partialDeallocation(uint120 paymentAmount, uint120 allocateAmount, uint120 deallocateAmount)
        public
    {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_ALLOCATION_AMOUNT, MAX_ALLOCATION_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, allocateAmount));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        authorizePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        CashbackRewards.RewardState memory initialRewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        uint256 initialCampaignBalance = usdc.balanceOf(unlimitedCashbackCampaign);

        bytes memory deallocateHookData = createCashbackHookData(paymentInfo, deallocateAmount);
        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), deallocateHookData);

        CashbackRewards.RewardState memory finalRewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(finalRewards.allocated, initialRewards.allocated - deallocateAmount);
        assertEq(finalRewards.distributed, initialRewards.distributed);
        assertEq(usdc.balanceOf(unlimitedCashbackCampaign), initialCampaignBalance);
    }

    /// @dev Successfully deallocates all allocated funds using max value
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate initially
    function test_success_fullDeallocationWithMaxValue(uint120 paymentAmount, uint120 allocateAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        authorizePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        CashbackRewards.RewardState memory initialRewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        uint256 initialCampaignBalance = usdc.balanceOf(unlimitedCashbackCampaign);

        // Special value for full deallocation
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](1);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: type(uint120).max});
        bytes memory deallocateHookData = abi.encode(paymentRewards);

        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), deallocateHookData);

        CashbackRewards.RewardState memory finalRewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(finalRewards.allocated, 0);
        assertEq(finalRewards.distributed, initialRewards.distributed);
        assertEq(usdc.balanceOf(unlimitedCashbackCampaign), initialCampaignBalance);
    }

    /// @dev Successfully deallocates zero when nothing was allocated
    /// @param paymentAmount Payment amount in USDC for the transaction
    function test_success_deallocateZeroWhenNothingAllocated(uint120 paymentAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        authorizePayment(paymentInfo);

        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](1);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: type(uint120).max});
        bytes memory deallocateHookData = abi.encode(paymentRewards);

        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), deallocateHookData);

        CashbackRewards.RewardState memory finalRewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(finalRewards.allocated, 0);
        assertEq(finalRewards.distributed, 0);
    }

    /// @dev Successfully processes multiple deallocations for same payment
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate initially
    function test_success_multipleDeallocationsSamePayment(uint120 paymentAmount, uint120 allocateAmount) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_ALLOCATION_AMOUNT, MAX_ALLOCATION_AMOUNT));
        uint120 firstDeallocate = allocateAmount / 2;
        uint120 secondDeallocate = allocateAmount / 2;

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        authorizePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        bytes memory firstDeallocateData = createCashbackHookData(paymentInfo, firstDeallocate);
        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), firstDeallocateData);

        CashbackRewards.RewardState memory midRewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(midRewards.allocated, allocateAmount - firstDeallocate);

        bytes memory secondDeallocateData = createCashbackHookData(paymentInfo, secondDeallocate);
        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), secondDeallocateData);

        CashbackRewards.RewardState memory finalRewards = getRewardsInfo(paymentInfo, unlimitedCashbackCampaign);
        assertEq(finalRewards.allocated, allocateAmount - firstDeallocate - secondDeallocate);
        assertEq(finalRewards.distributed, 0);
    }

    /// @dev Successfully processes batch deallocations for multiple payments
    /// @param firstPaymentAmount Payment amount in USDC for first transaction
    /// @param secondPaymentAmount Payment amount in USDC for second transaction
    /// @param firstAllocation Allocation amount for first payment
    /// @param secondAllocation Allocation amount for second payment
    /// @param firstDeallocate Deallocation amount for first payment
    /// @param secondDeallocate Deallocation amount for second payment
    function test_success_batchDeallocateMultiplePayments(
        uint120 firstPaymentAmount,
        uint120 secondPaymentAmount,
        uint120 firstAllocation,
        uint120 secondAllocation,
        uint120 firstDeallocate,
        uint120 secondDeallocate
    ) public {
        // Use reasonable bounds to ensure buyer can afford both payments
        firstPaymentAmount = uint120(bound(firstPaymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        secondPaymentAmount = uint120(bound(secondPaymentAmount, MIN_PAYMENT_AMOUNT, 1000000e6)); // Max 1M USDC
        firstAllocation = uint120(bound(firstAllocation, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));
        secondAllocation = uint120(bound(secondAllocation, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT / 2));
        firstDeallocate = uint120(bound(firstDeallocate, MIN_REWARD_AMOUNT, firstAllocation));
        secondDeallocate = uint120(bound(secondDeallocate, MIN_REWARD_AMOUNT, secondAllocation));

        // Create two different payments
        AuthCaptureEscrow.PaymentInfo memory firstPayment = createPaymentInfo(buyer, firstPaymentAmount);
        firstPayment.salt = uint256(keccak256("first_payment"));

        AuthCaptureEscrow.PaymentInfo memory secondPayment = createPaymentInfo(buyer, secondPaymentAmount);
        secondPayment.salt = uint256(keccak256("second_payment"));

        // Authorize both payments and allocate rewards
        authorizePayment(firstPayment);
        authorizePayment(secondPayment);

        // Allocate rewards for both payments
        bytes memory firstAllocateData = createCashbackHookData(firstPayment, firstAllocation);
        bytes memory secondAllocateData = createCashbackHookData(secondPayment, secondAllocation);

        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), firstAllocateData);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), secondAllocateData);

        // Create batch deallocation hook data
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](2);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: firstPayment, payoutAmount: firstDeallocate});
        paymentRewards[1] = CashbackRewards.PaymentReward({paymentInfo: secondPayment, payoutAmount: secondDeallocate});
        bytes memory batchHookData = abi.encode(paymentRewards, true);

        // Get initial states
        CashbackRewards.RewardState memory firstRewardsBefore = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsBefore =
            getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        // Execute batch deallocation
        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), batchHookData);

        // Verify both deallocations were processed
        CashbackRewards.RewardState memory firstRewardsAfter = getRewardsInfo(firstPayment, unlimitedCashbackCampaign);
        CashbackRewards.RewardState memory secondRewardsAfter = getRewardsInfo(secondPayment, unlimitedCashbackCampaign);

        assertEq(firstRewardsAfter.allocated, firstRewardsBefore.allocated - firstDeallocate);
        assertEq(secondRewardsAfter.allocated, secondRewardsBefore.allocated - secondDeallocate);
        assertEq(firstRewardsAfter.distributed, firstRewardsBefore.distributed);
        assertEq(secondRewardsAfter.distributed, secondRewardsBefore.distributed);
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Verifies RewardFailed event is emitted when attempting to deallocate zero amount with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Allocation amount to set up for deallocation
    function test_edge_emitsRewardFailed_onZeroAmount_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // First allocate some funds
        authorizePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        // Try to deallocate zero amount with revertOnError = false
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, 0);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            0,
            CashbackRewards.RewardOperation.DEALLOCATE,
            abi.encodeWithSelector(CashbackRewards.ZeroPayoutAmount.selector)
        );

        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when payment token differs from campaign token with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Allocation amount to set up for deallocation
    /// @param deallocateAmount Deallocation amount to attempt
    /// @param wrongToken Incorrect token address used in payment
    function test_edge_emitsRewardFailed_onWrongToken_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount,
        uint120 deallocateAmount,
        address wrongToken
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, allocateAmount));
        vm.assume(wrongToken != address(usdc) && wrongToken != address(0));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        // First allocate some funds
        authorizePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        // Change token for deallocate
        paymentInfo.token = wrongToken; // Wrong token
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, deallocateAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            deallocateAmount,
            CashbackRewards.RewardOperation.DEALLOCATE,
            abi.encodeWithSelector(CashbackRewards.TokenMismatch.selector)
        );

        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies RewardFailed event is emitted when attempting to deallocate for uncollected payment with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param deallocateAmount Deallocation amount to attempt
    function test_edge_emitsRewardFailed_onPaymentNotCollected_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 deallocateAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);
        bytes memory hookData = createCashbackHookDataNoRevert(paymentInfo, deallocateAmount);
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Don't authorize the payment - leave it uncollected

        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            paymentInfoHash,
            deallocateAmount,
            CashbackRewards.RewardOperation.DEALLOCATE,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);
    }

    /// @dev Verifies mixed batch processing handles valid and invalid deallocations correctly with revertOnError=false
    /// @param paymentAmount Payment amount in USDC for both transactions
    /// @param allocateAmount Allocation amount to set up for deallocation
    /// @param deallocateAmount Deallocation amount to attempt
    function test_edge_mixedPayments_someValidSomeInvalid_whenRevertOnErrorFalse(
        uint120 paymentAmount,
        uint120 allocateAmount,
        uint120 deallocateAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_REWARD_AMOUNT, MAX_REWARD_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, allocateAmount));

        // Create valid payment (authorized and allocated)
        AuthCaptureEscrow.PaymentInfo memory validPayment = createPaymentInfo(buyer, paymentAmount);
        validPayment.salt = uint256(keccak256("valid"));
        authorizePayment(validPayment);
        bytes memory allocateHookData = createCashbackHookData(validPayment, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        // Create invalid payment (not authorized)
        AuthCaptureEscrow.PaymentInfo memory invalidPayment = createPaymentInfo(buyer, paymentAmount);
        invalidPayment.salt = uint256(keccak256("invalid"));

        bytes memory hookData =
            createMixedCashbackHookDataNoRevert(validPayment, deallocateAmount, invalidPayment, deallocateAmount);
        bytes32 invalidPaymentHash = escrow.getHash(invalidPayment);

        // Expect event for the invalid payment
        vm.expectEmit(true, true, true, true);
        emit CashbackRewards.RewardFailed(
            invalidPaymentHash,
            deallocateAmount,
            CashbackRewards.RewardOperation.DEALLOCATE,
            abi.encodeWithSelector(CashbackRewards.PaymentNotCollected.selector)
        );

        // Should not revert, but process the valid payment and emit event for invalid
        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), hookData);

        // Verify the valid payment was processed
        CashbackRewards.RewardState memory validRewards = getRewardsInfo(validPayment, unlimitedCashbackCampaign);
        assertEq(validRewards.allocated, allocateAmount - deallocateAmount);

        // Verify the invalid payment was not processed
        CashbackRewards.RewardState memory invalidRewards = getRewardsInfo(invalidPayment, unlimitedCashbackCampaign);
        assertEq(invalidRewards.allocated, 0);
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies correct Flywheel event emission for successful deallocation
    /// @param paymentAmount Payment amount in USDC for the transaction
    /// @param allocateAmount Amount to allocate initially
    /// @param deallocateAmount Amount to deallocate
    function test_onDeallocate_emitsFlywheelEvents(
        uint120 paymentAmount,
        uint120 allocateAmount,
        uint120 deallocateAmount
    ) public {
        paymentAmount = uint120(bound(paymentAmount, MIN_PAYMENT_AMOUNT, MAX_PAYMENT_AMOUNT));
        allocateAmount = uint120(bound(allocateAmount, MIN_ALLOCATION_AMOUNT, MAX_ALLOCATION_AMOUNT));
        deallocateAmount = uint120(bound(deallocateAmount, MIN_REWARD_AMOUNT, allocateAmount));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(buyer, paymentAmount);

        authorizePayment(paymentInfo);
        bytes memory allocateHookData = createCashbackHookData(paymentInfo, allocateAmount);
        vm.prank(manager);
        flywheel.allocate(unlimitedCashbackCampaign, address(usdc), allocateHookData);

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        vm.expectEmit(true, true, true, true);
        emit Flywheel.PayoutDeallocated(
            unlimitedCashbackCampaign,
            address(usdc),
            bytes32(bytes20(buyer)),
            deallocateAmount,
            abi.encodePacked(paymentInfoHash)
        );

        bytes memory deallocateHookData = createCashbackHookData(paymentInfo, deallocateAmount);
        vm.prank(manager);
        flywheel.deallocate(unlimitedCashbackCampaign, address(usdc), deallocateHookData);
    }
}
