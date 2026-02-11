// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

import {Flywheel} from "../Flywheel.sol";
import {CampaignHooks} from "../CampaignHooks.sol";
import {SimpleRewards} from "./SimpleRewards.sol";

/// @title CashbackRewards
///
/// @notice Reward buyers for their purchases made with the Commerce Payments Protocol (https://github.com/base/commerce-payments)
///
/// @dev Rewards must be made in the same token as the original payment token (cashback)
/// @dev Rewards can be made in any amount (supports %, fixed, etc.)
/// @dev Maximum reward percentage can be optionally configured per campaign
/// @dev Rewards can be made on any payment (supports custom filtering for platforms, wallets, merchants, etc.)
///
/// @author Coinbase
contract CashbackRewards is SimpleRewards {
    /// @notice Operation types for reward validation
    enum RewardOperation {
        REWARD,
        ALLOCATE,
        DEALLOCATE,
        DISTRIBUTE
    }

    /// @notice Tracks rewards info per payment per campaign
    struct RewardState {
        /// @dev Amount of reward allocated for this payment
        uint120 allocated;
        /// @dev Amount of reward distributed for this payment
        uint120 distributed;
    }

    /// @notice A struct for a payment reward
    struct PaymentReward {
        /// @dev The payment to reward
        AuthCaptureEscrow.PaymentInfo paymentInfo;
        /// @dev The reward payout amount
        uint120 payoutAmount;
    }

    /// @notice The divisor for max reward basis points (10_000 = 100%)
    uint256 public constant BASIS_POINTS_100_PERCENT = 10_000;

    /// @notice The escrow contract to track payment states and calculate payment hash
    AuthCaptureEscrow public immutable escrow;

    /// @notice Tracks an optional maximum reward percentage per campaign in basis points (10_000 = 100%)
    mapping(address campaign => uint256 maxRewardBasisPoints) public maxRewardBasisPoints;

    /// @notice Tracks rewards info per campaign per payment
    mapping(address campaign => mapping(bytes32 paymentHash => RewardState rewardState)) public rewards;

    /// @notice Emitted when a reward operation fails but revertOnError is false
    ///
    /// @param paymentInfoHash The attempted payment
    /// @param amount The attempted reward amount
    /// @param operation The attempted reward operation
    /// @param error The error bytes
    event RewardFailed(bytes32 indexed paymentInfoHash, uint256 amount, RewardOperation operation, bytes error);

    /// @notice Thrown when the allocated amount is less than the amount being deallocated or distributed
    error InsufficientAllocation(uint120 amount, uint120 allocated);

    /// @notice Thrown when the payment amount is invalid
    error ZeroPayoutAmount();

    /// @notice Thrown when the payment token does not match the campaign token
    error TokenMismatch();

    /// @notice Thrown when the payment has not been collected
    error PaymentNotCollected();

    /// @notice Thrown when the reward amount exceeds the maximum allowed percentage
    error RewardExceedsMaxPercentage(
        bytes32 paymentInfoHash, uint120 maxAllowedRewardAmount, uint120 excessRewardAmount
    );

    /// @notice Constructor
    ///
    /// @param flywheel_ The Flywheel core protocol contract address
    /// @param escrow_ The AuthCaptureEscrow contract address
    constructor(address flywheel_, address escrow_) SimpleRewards(flywheel_) {
        escrow = AuthCaptureEscrow(escrow_);
    }

    /// @inheritdoc CampaignHooks
    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal override {
        (address owner, address manager, string memory uri, uint16 maxRewardBasisPoints_) =
            abi.decode(hookData, (address, address, string, uint16));
        owners[campaign] = owner;
        managers[campaign] = manager;
        campaignURI[campaign] = uri;
        maxRewardBasisPoints[campaign] = uint256(maxRewardBasisPoints_);
        emit CampaignCreated(campaign, owner, manager, uri);
    }

    /// @inheritdoc CampaignHooks
    function _onSend(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        onlyManager(sender, campaign)
        returns (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        (PaymentReward[] memory paymentRewards, bool revertOnError) = abi.decode(hookData, (PaymentReward[], bool));
        (uint256 inputLen, uint256 outputLen) = (paymentRewards.length, 0);
        payouts = new Flywheel.Payout[](inputLen);

        for (uint256 i = 0; i < inputLen; i++) {
            // Validate the payment reward
            (bytes32 paymentInfoHash, uint120 amount, address payer, bytes memory err) =
                _validatePaymentReward(paymentRewards[i], campaign, token, RewardOperation.REWARD);

            // Skip this reward if there was a non-reverted error
            if (err.length > 0) {
                _revertOrEmitError(revertOnError, paymentInfoHash, amount, RewardOperation.REWARD, err);
                continue;
            }

            // Add the payout amount to the distributed amount
            rewards[campaign][paymentInfoHash].distributed += amount;

            // Append to return array
            payouts[outputLen++] =
                Flywheel.Payout({recipient: payer, amount: amount, extraData: abi.encodePacked(paymentInfoHash)});
        }

        // Resize array to actual output length
        assembly {
            mstore(payouts, outputLen)
        }
    }

    /// @inheritdoc CampaignHooks
    function _onAllocate(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Allocation[] memory allocations)
    {
        (PaymentReward[] memory paymentRewards, bool revertOnError) = abi.decode(hookData, (PaymentReward[], bool));
        (uint256 inputLen, uint256 outputLen) = (paymentRewards.length, 0);
        allocations = new Flywheel.Allocation[](inputLen);

        for (uint256 i = 0; i < inputLen; i++) {
            // Validate the payment reward
            (bytes32 paymentInfoHash, uint120 amount, address payer, bytes memory err) =
                _validatePaymentReward(paymentRewards[i], campaign, token, RewardOperation.ALLOCATE);

            // Skip this reward if there was a non-reverted error
            if (err.length > 0) {
                _revertOrEmitError(revertOnError, paymentInfoHash, amount, RewardOperation.ALLOCATE, err);
                continue;
            }

            // Add the payout amount to the allocated amount
            rewards[campaign][paymentInfoHash].allocated += amount;

            // Append to return array
            allocations[outputLen++] = Flywheel.Allocation({
                key: bytes32(bytes20(payer)),
                amount: amount,
                extraData: abi.encodePacked(paymentInfoHash)
            });
        }

        // Resize array to actual output length
        assembly {
            mstore(allocations, outputLen)
        }
    }

    /// @inheritdoc CampaignHooks
    function _onDeallocate(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Allocation[] memory allocations)
    {
        (PaymentReward[] memory paymentRewards, bool revertOnError) = abi.decode(hookData, (PaymentReward[], bool));
        (uint256 inputLen, uint256 outputLen) = (paymentRewards.length, 0);
        allocations = new Flywheel.Allocation[](inputLen);

        for (uint256 i = 0; i < inputLen; i++) {
            // Validate the payment reward
            (bytes32 paymentInfoHash, uint120 amount, address payer, bytes memory err) =
                _validatePaymentReward(paymentRewards[i], campaign, token, RewardOperation.DEALLOCATE);

            // Skip this reward if there was a non-reverted error
            if (err.length > 0) {
                _revertOrEmitError(revertOnError, paymentInfoHash, amount, RewardOperation.DEALLOCATE, err);
                continue;
            }

            // Determine correct deallocation amount (special case of max uint120 means deallocate all allocated)
            uint120 allocated = rewards[campaign][paymentInfoHash].allocated;
            if (amount == type(uint120).max) amount = allocated;

            // Check sufficient allocation
            if (allocated < amount) revert InsufficientAllocation(amount, allocated);

            // Decrease allocated amount for payment
            rewards[campaign][paymentInfoHash].allocated = allocated - amount;

            // Append to return array
            allocations[outputLen++] = Flywheel.Allocation({
                key: bytes32(bytes20(payer)),
                amount: amount,
                extraData: abi.encodePacked(paymentInfoHash)
            });
        }

        // Resize array to actual output length
        assembly {
            mstore(allocations, outputLen)
        }
    }

    /// @inheritdoc CampaignHooks
    function _onDistribute(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        onlyManager(sender, campaign)
        returns (
            Flywheel.Distribution[] memory distributions,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        (PaymentReward[] memory paymentRewards, bool revertOnError) = abi.decode(hookData, (PaymentReward[], bool));
        (uint256 inputLen, uint256 outputLen) = (paymentRewards.length, 0);
        distributions = new Flywheel.Distribution[](inputLen);

        for (uint256 i = 0; i < inputLen; i++) {
            // Validate the payment reward
            (bytes32 paymentInfoHash, uint120 amount, address payer, bytes memory err) =
                _validatePaymentReward(paymentRewards[i], campaign, token, RewardOperation.DISTRIBUTE);

            // Skip this reward if there was a non-reverted error
            if (err.length > 0) {
                _revertOrEmitError(revertOnError, paymentInfoHash, amount, RewardOperation.DISTRIBUTE, err);
                continue;
            }

            // Check sufficient allocation
            uint120 allocated = rewards[campaign][paymentInfoHash].allocated;
            if (allocated < amount) revert InsufficientAllocation(amount, allocated);

            // Shift the payout amount from allocated to distributed
            rewards[campaign][paymentInfoHash].allocated = allocated - amount;
            rewards[campaign][paymentInfoHash].distributed += amount;

            // Append to return array
            distributions[outputLen++] = Flywheel.Distribution({
                recipient: payer,
                key: bytes32(bytes20(payer)),
                amount: amount,
                extraData: abi.encodePacked(paymentInfoHash)
            });
        }

        // Resize array to actual output length
        assembly {
            mstore(distributions, outputLen)
        }
    }

    /// @notice Handles error with either a revert or event emission.
    ///
    /// @param err The error bytes to revert with or emit
    /// @param revertOnError Whether to revert on error or emit RewardFailed event
    /// @param paymentInfoHash The payment info hash for the failed reward
    /// @param amount The payout amount that failed
    /// @param operation The RewardOperation type
    function _revertOrEmitError(
        bool revertOnError,
        bytes32 paymentInfoHash,
        uint256 amount,
        RewardOperation operation,
        bytes memory err
    ) internal {
        if (revertOnError) {
            assembly {
                revert(add(err, 0x20), mload(err))
            }
        } else {
            emit RewardFailed(paymentInfoHash, amount, operation, err);
        }
    }

    /// @dev Validates a payment reward and returns the payment info hash
    ///
    /// @param paymentReward The payment reward
    /// @param campaign The campaign address
    /// @param token The campaign token
    /// @param operation The type of operation being performed
    function _validatePaymentReward(
        PaymentReward memory paymentReward,
        address campaign,
        address token,
        RewardOperation operation
    ) internal view returns (bytes32 paymentInfoHash, uint120 amount, address payer, bytes memory err) {
        (paymentInfoHash, amount, payer) =
            (escrow.getHash(paymentReward.paymentInfo), paymentReward.payoutAmount, paymentReward.paymentInfo.payer);

        // Check reward amount non-zero
        if (amount == 0) {
            return (paymentInfoHash, amount, payer, abi.encodeWithSelector(ZeroPayoutAmount.selector));
        }

        // Check the token matches the payment token
        if (paymentReward.paymentInfo.token != token) {
            return (paymentInfoHash, amount, payer, abi.encodeWithSelector(TokenMismatch.selector));
        }

        // Check payment has been collected
        (bool hasCollectedPayment, uint120 capturableAmount, uint120 refundableAmount) =
            escrow.paymentState(paymentInfoHash);
        if (!hasCollectedPayment) {
            return (paymentInfoHash, amount, payer, abi.encodeWithSelector(PaymentNotCollected.selector));
        }

        // Early return if deallocating, skips percentage validation
        if (operation == RewardOperation.DEALLOCATE) return (paymentInfoHash, amount, payer, "");

        // Early return if no max reward percentage is configured
        uint256 maxRewardBps = maxRewardBasisPoints[campaign];
        if (maxRewardBps == 0) return (paymentInfoHash, amount, payer, "");

        // Payment amount is the captured amount that has not been refunded i.e. "refundable" amount
        uint120 paymentAmount = refundableAmount;
        uint120 previouslyRewardedAmount = rewards[campaign][paymentInfoHash].distributed;

        // If allocating, add the pre-capture and pre-distribution amounts too to prevent allocating more than the max allowed reward for this payment
        if (operation == RewardOperation.ALLOCATE) {
            paymentAmount += capturableAmount;
            previouslyRewardedAmount += rewards[campaign][paymentInfoHash].allocated;
        }

        // Check total reward amount doesn't exceed the max allowed reward for this payment
        uint120 totalRewardAmount = previouslyRewardedAmount + amount;
        uint120 maxAllowedRewardAmount = uint120(paymentAmount * maxRewardBps / BASIS_POINTS_100_PERCENT);
        if (totalRewardAmount > maxAllowedRewardAmount) {
            err = abi.encodeWithSelector(
                RewardExceedsMaxPercentage.selector,
                paymentInfoHash,
                maxAllowedRewardAmount,
                totalRewardAmount - maxAllowedRewardAmount
            );
        }
        return (paymentInfoHash, amount, payer, err);
    }
}
