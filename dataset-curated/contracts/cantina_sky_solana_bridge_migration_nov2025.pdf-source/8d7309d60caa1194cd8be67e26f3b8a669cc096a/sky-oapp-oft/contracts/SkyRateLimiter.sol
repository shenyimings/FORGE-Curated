// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {
    RateLimit,
    RateLimitConfig,
    RateLimitDirection,
    RateLimitAccountingType,
    ISkyRateLimiter
} from "./interfaces/ISkyRateLimiter.sol";

/**
 * @title SkyRateLimiter
 * @dev Abstract contract for implementing net and gross rate limiting functionality.
 * @dev Toggle between net and gross accounting by calling `_setRateLimitAccountingType`.
 * ---------------------------------------------------------------------------------------------------------------------
 * Net accounting allows two operations to offset each other's net impact (e.g., inflow v.s. outflow of assets).
 * A flexible rate limit that grows during congestive periods and shrinks during calm periods could give some
 * leeway when someone tries to forcefully congest the network, while still preventing huge amounts to be sent at once.
 * ---------------------------------------------------------------------------------------------------------------------
 * Gross accounting does not allow any offsetting and will revert if the amount to be sent or received,
 * is greater than the available capacity.
 * Designed to be inherited by other contracts requiring rate limiting to protect resources/services from excessive use.
 */
abstract contract SkyRateLimiter is ISkyRateLimiter {
    RateLimitAccountingType public rateLimitAccountingType;

    // Tracks rate limits for outbound transactions to a dstEid.
    mapping(uint32 dstEid => RateLimit) public outboundRateLimits;
    // Tracks rate limits for inbound transactions from a srcEid.
    mapping(uint32 srcEid => RateLimit) public inboundRateLimits;

    /**
     * @notice Get the current amount that can be sent to this destination endpoint id for the given rate limit window.
     * @param _dstEid The destination endpoint id.
     * @return currentAmountInFlight The current amount that was sent in this window.
     * @return amountCanBeSent The amount that can be sent.
     */
    function getAmountCanBeSent(
        uint32 _dstEid
    ) public view virtual returns (uint256 currentAmountInFlight, uint256 amountCanBeSent) {
        RateLimit storage orl = outboundRateLimits[_dstEid];
        return _amountCanBeSent(orl.amountInFlight, orl.lastUpdated, orl.limit, orl.window);
    }

    /**
     * @notice Get the current amount that can be received from the source endpoint id for the given rate limit window.
     * @param _srcEid The source endpoint id.
     * @return currentAmountInFlight The current amount that has been received in this window.
     * @return amountCanBeReceived The amount that can be received.
     */
    function getAmountCanBeReceived(
        uint32 _srcEid
    ) public view virtual returns (uint256 currentAmountInFlight, uint256 amountCanBeReceived) {
        RateLimit storage irl = inboundRateLimits[_srcEid];
        return _amountCanBeReceived(irl.amountInFlight, irl.lastUpdated, irl.limit, irl.window);
    }

    /**
     * @notice Sets the rate limits.
     * @param _rateLimitConfigs A `RateLimitConfig[]` array representing the rate limit configurations.
     * @param _direction Indicates whether the rate limits being set are for outbound or inbound.
     */
    function _setRateLimits(RateLimitConfig[] memory _rateLimitConfigs, RateLimitDirection _direction) internal virtual {
        unchecked {
            for (uint256 i = 0; i < _rateLimitConfigs.length; i++) {
                RateLimit storage rateLimit = _direction == RateLimitDirection.Outbound
                    ? outboundRateLimits[_rateLimitConfigs[i].eid]
                    : inboundRateLimits[_rateLimitConfigs[i].eid];

                // Checkpoint the existing rate limit to not retroactively apply the new decay rate.
                _checkAndUpdateRateLimit(_rateLimitConfigs[i].eid, 0, _direction);

                // Does NOT reset the amountInFlight/lastUpdated of an existing rate limit.
                rateLimit.limit = _rateLimitConfigs[i].limit;
                rateLimit.window = _rateLimitConfigs[i].window;
            }
        }
        emit RateLimitsChanged(_rateLimitConfigs, _direction);
    }

    /**
     * @notice Resets the rate limits (sets amountInFlight to 0) for the given endpoint ids.
     * @dev This is useful when the rate limit accounting type is changed.
     * @param _eids The endpoint ids to reset the rate limits for.
     * @param _direction The direction of the rate limits to reset.
     */
    function _resetRateLimits(uint32[] memory _eids, RateLimitDirection _direction) internal virtual {
        for (uint256 i = 0; i < _eids.length; i++) {
            RateLimit storage rateLimit = _direction == RateLimitDirection.Outbound
                ? outboundRateLimits[_eids[i]]
                : inboundRateLimits[_eids[i]];

            rateLimit.amountInFlight = 0;
            rateLimit.lastUpdated = uint128(block.timestamp);
        }
        emit RateLimitsReset(_eids, _direction);
    }

     /**
     * @notice Sets the rate limit accounting type.
     * @dev You may want to call `_resetRateLimits` after changing the rate limit accounting type.
     * @param _rateLimitAccountingType The new rate limit accounting type.
     */
    function _setRateLimitAccountingType(RateLimitAccountingType _rateLimitAccountingType) internal {
        rateLimitAccountingType = _rateLimitAccountingType;
        emit RateLimitAccountingTypeSet(_rateLimitAccountingType);
    }

    /**
     * @dev Calculates current amount in flight and the available capacity based on configuration and time elapsed.
     * Applies a linear decay to compute how much 'amountInFlight' remains based on the time elapsed since last update.
     * @param _amountInFlight The total amount that was in flight at the last update.
     * @param _lastUpdated The timestamp (in seconds) when the last update occurred.
     * @param _limit The maximum allowable amount within the specified window.
     * @param _window The time window (in seconds) for which the limit applies.
     *
     * @return currentAmountInFlight The decayed amount of in-flight based on the elapsed time since lastUpdated.
     * @return availableCapacity The amount of capacity available for new activity.
     * @dev If the time since lastUpdated exceeds the window:
     *      - currentAmountInFlight is 0.
     *      - availableCapacity is the full limit.
     */
    function _calculateDecay(
        uint256 _amountInFlight,
        uint128 _lastUpdated,
        uint256 _limit,
        uint48 _window
    ) internal view returns (uint256 currentAmountInFlight, uint256 availableCapacity) {
        uint256 timeSinceLastUpdate = block.timestamp - _lastUpdated;
        if (timeSinceLastUpdate >= _window) {
            return (0, _limit);
        } else {
            uint256 decay = (_limit * timeSinceLastUpdate) / _window;
            currentAmountInFlight = _amountInFlight > decay ? _amountInFlight - decay : 0;
            availableCapacity = _limit > currentAmountInFlight ? _limit - currentAmountInFlight : 0;
        }
    }

    /**
     * @notice Checks current amount in flight and amount that can be sent for a given rate limit window.
     * @param _amountInFlight The amount in the current window.
     * @param _lastUpdated Timestamp representing the last time the rate limit was checked or updated.
     * @param _limit This represents the maximum allowed amount within a given window.
     * @param _window Defines the duration of the rate limiting window.
     * @return currentAmountInFlight The amount in the current window.
     * @return amountCanBeSent The amount that can be sent.
     */
    function _amountCanBeSent(
        uint256 _amountInFlight,
        uint128 _lastUpdated,
        uint256 _limit,
        uint48 _window
    ) internal view virtual returns (uint256 currentAmountInFlight, uint256 amountCanBeSent) {
        (currentAmountInFlight, amountCanBeSent) = _calculateDecay(_amountInFlight, _lastUpdated, _limit, _window);
    }

    /**
     * @notice Checks current amount in flight and amount that can be received for a given rate limit window.
     * @param _amountInFlight The amount in the current window.
     * @param _lastUpdated Timestamp representing the last time the rate limit was checked or updated.
     * @param _limit This represents the maximum allowed amount within a given window.
     * @param _window Defines the duration of the rate limiting window.
     * @return currentAmountInFlight The amount in the current window.
     * @return amountCanBeReceived The amount that can be received.
     */
    function _amountCanBeReceived(
        uint256 _amountInFlight,
        uint128 _lastUpdated,
        uint256 _limit,
        uint48 _window
    ) internal view virtual returns (uint256 currentAmountInFlight, uint256 amountCanBeReceived) {
        (currentAmountInFlight, amountCanBeReceived) = _calculateDecay(_amountInFlight, _lastUpdated, _limit, _window);
    }
    
    /**
     * @notice Checks and updates the rate limit based on the endpoint ID and amount.
     * @param _eid The endpoint ID for which the rate limit needs to be checked and updated.
     * @param _amount The amount to add to the current amount in flight.
     * @param _direction The direction (inbound or outbound) of the rate limits being checked.
     */
    function _checkAndUpdateRateLimit(uint32 _eid, uint256 _amount, RateLimitDirection _direction) internal {
        // Select the correct mapping based on the direction of the rate limit
        RateLimit storage rl = _direction == RateLimitDirection.Outbound
            ? outboundRateLimits[_eid]
            : inboundRateLimits[_eid];

        // Calculate current amount in flight and available capacity
        (uint256 currentAmountInFlight, uint256 availableCapacity) = _calculateDecay(
            rl.amountInFlight,
            rl.lastUpdated,
            rl.limit,
            rl.window
        );

        // Check if the requested amount exceeds the available capacity
        if (_amount > availableCapacity) revert RateLimitExceeded();

        // Update the rate limit with the new amount in flight and the current timestamp
        rl.amountInFlight = currentAmountInFlight + _amount;
        rl.lastUpdated = uint128(block.timestamp);

        if (rateLimitAccountingType == RateLimitAccountingType.Net) {
            RateLimit storage oppositeRL = _direction == RateLimitDirection.Outbound
                ? inboundRateLimits[_eid]
                : outboundRateLimits[_eid];
            (uint256 otherCurrentAmountInFlight,) = _calculateDecay(
                oppositeRL.amountInFlight,
                oppositeRL.lastUpdated,
                oppositeRL.limit,
                oppositeRL.window
            );
            unchecked {
                oppositeRL.amountInFlight = otherCurrentAmountInFlight > _amount ? otherCurrentAmountInFlight - _amount : 0;
            }
            oppositeRL.lastUpdated = uint128(block.timestamp);
        }
    }
}