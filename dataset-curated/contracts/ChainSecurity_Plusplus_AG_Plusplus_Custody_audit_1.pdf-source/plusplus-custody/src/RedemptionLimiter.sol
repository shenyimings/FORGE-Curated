// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title RedemptionLimiter
/// @notice Rolling 24-hour per-user amount limiter (token-bucket / allowance refill).
/// @dev Intended to be inherited by contracts that need simple rate limiting.
/// @author Plusplus AG (dev@plusplus.swiss)
/// @custom:security-contact security@plusplus.swiss
abstract contract RedemptionLimiter {
    /// @notice Per-operator quota for rate-limiting deposit redemptions
    struct RedemptionQuota {
        uint192 availableAmount; // Remaining amount available for redemption
        uint64 lastRefillTime; // Last time the quota was used/refilled
    }

    /// @notice Per-operator redemption quota tracking
    mapping(address => RedemptionQuota) public userRedemptionQuota;
    /// @notice Daily redemption limit per operator (in asset units)
    mapping(address => uint192) public dailyRedemptionLimit;

    /// @notice Emitted when a user's daily limit is (re)configured.
    event DailyRedemptionLimitSet(address indexed user, uint192 dailyLimit);

    /// @notice Thrown when trying to use a quota for a user without a limit set
    error LimitNotSet();
    /// @notice Thrown when trying to consume more than the available quota
    error WithdrawalLimitExceeded();

    /// @notice Configure or update an operator's daily redemption limit and reset their rolling window to full.
    /// @dev Access control is left to the child contract; call this from a role/owner-gated setter.
    /// @param user The operator whose limit is being set.
    /// @param dailyLimit The daily quota (in asset units) for the rolling window.
    function _setDailyRedemptionLimit(address user, uint192 dailyLimit) internal virtual {
        dailyRedemptionLimit[user] = dailyLimit;

        // Initialize/refresh the current window to full capacity.
        RedemptionQuota storage quota = userRedemptionQuota[user];
        quota.availableAmount = dailyLimit;
        quota.lastRefillTime = uint64(block.timestamp);

        emit DailyRedemptionLimitSet(user, dailyLimit);
    }

    /// @notice Consume quota for an arbitrary user
    /// @dev Recomputes the token-bucket refill since the last update, clamps to limit, then deducts.
    ///      Very small time deltas may result in zero refill due to integer division.
    ///      Reverts with {LimitNotSet} if the user's daily limit is zero.
    ///      Reverts with {WithdrawalLimitExceeded} if `amount` exceeds the available quota.
    /// @param user The user whose quota to consume.
    /// @param amount The amount to deduct from the available quota (in asset units).
    function _useRedemptionQuota(address user, uint256 amount) internal virtual {
        uint192 limit = dailyRedemptionLimit[user];
        if (limit == 0) revert LimitNotSet();

        RedemptionQuota memory quota = userRedemptionQuota[user];

        // Refill quota based on time elapsed since last refill
        uint256 nowTs = block.timestamp;
        uint256 timeElapsed = nowTs - quota.lastRefillTime;
        if (timeElapsed > 0) {
            uint256 refillAmount = (limit * timeElapsed) / 1 days;
            uint256 newAvailable = quota.availableAmount + refillAmount;
            if (newAvailable > limit) newAvailable = limit;

            quota.availableAmount = uint192(newAvailable);
            quota.lastRefillTime = uint64(nowTs);
        }

        // Check if enough quota is available
        if (amount > quota.availableAmount) revert WithdrawalLimitExceeded();

        quota.availableAmount -= uint192(amount);
        userRedemptionQuota[user] = quota;
    }

    /// @notice Convenience helper to consume quota for `msg.sender`.
    /// @dev Calls {_useRedemptionQuota} with `user = msg.sender`.
    /// @param amount The amount to deduct from the caller's available quota.
    function _useMyRedemptionQuota(uint256 amount) internal virtual {
        _useRedemptionQuota(msg.sender, amount);
    }

    /// @notice Compute how much a user could redeem right now, including accrued refill.
    /// @dev Off-chain callers should prefer this view; on-chain callers pay read gas only.
    /// @param user The user to query.
    /// @return available The currently available quota amount in asset units.
    function availableRedemptionQuota(address user) external view returns (uint256 available) {
        uint256 limit = dailyRedemptionLimit[user];
        if (limit == 0) return 0;

        RedemptionQuota memory quota = userRedemptionQuota[user];

        // Calculate potential refill based on time elapsed
        uint256 timeElapsed = block.timestamp - quota.lastRefillTime;
        uint256 refillAmount = (limit * timeElapsed) / 1 days;
        available = uint256(quota.availableAmount) + refillAmount;
        if (available > limit) available = limit;

        return available;
    }
}
