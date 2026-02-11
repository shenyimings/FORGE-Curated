// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @notice Rate Limit struct
 * @param lastUpdated Timestamp representing the last time the rate limit was checked or updated.
 * @param window Defines the duration of the rate limiting window.
 * @param amountInFlight Current amount within the rate limit window.
 * @param limit This represents the maximum allowed amount within a given window.
 */
struct RateLimit {
    uint128 lastUpdated;    // 16 bytes
    uint48 window;          // 6 bytes
    uint256 amountInFlight; // 32 bytes (new slot)
    uint256 limit;          // 32 bytes (new slot)
}

/**
* @notice Rate Limit Configuration struct.
 * @param eid The endpoint id.
 * @param window Defines the duration of the rate limiting window.
 * @param limit This represents the maximum allowed amount within a given window.
 */
struct RateLimitConfig {
    uint32 eid;      // 4 bytes
    uint48 window;   // 6 bytes
    uint256 limit;   // 32 bytes (new slot)
}

// @dev Define an enum to clearly distinguish between inbound and outbound rate limits.
enum RateLimitDirection {
    Inbound,
    Outbound
}

// @dev Define an enum to distinguish between net and gross accounting types for rate limits.
enum RateLimitAccountingType {
    Net,
    Gross
}

/**
 * @notice Interface for the SkyRateLimiter.
 * @dev This interface defines the functions and events for managing rate limits for both inbound and outbound flows.
 */
interface ISkyRateLimiter {
    /**
     * @notice Emitted when _setRateLimits occurs.
     * @param rateLimitConfigs An array of `RateLimitConfig` structs representing configurations set per endpoint id.
     * - `eid`: The source / destination endpoint id (depending on direction).
     * - `window`: Defines the duration of the rate limiting window.
     * - `limit`: This represents the maximum allowed amount within a given window.
     * @param direction Specifies whether the outbound or inbound rates were changed.
     */
    event RateLimitsChanged(RateLimitConfig[] rateLimitConfigs, RateLimitDirection direction);
    event RateLimitAccountingTypeSet(RateLimitAccountingType newRateLimitAccountingType);
    event RateLimitsReset(uint32[] eids, RateLimitDirection direction);

    // @dev Error that is thrown when an amount exceeds the rate limit for a given direction.
    error RateLimitExceeded();

    /**
     * @notice Get the current amount that can be sent to this destination endpoint id for the given rate limit window.
     * @param dstEid The destination endpoint id.
     * @return currentAmountInFlight The current amount that was sent in this window.
     * @return amountCanBeSent The amount that can be sent.
     */
    function getAmountCanBeSent(
        uint32 dstEid
    ) external view returns (uint256 currentAmountInFlight, uint256 amountCanBeSent);

    /**
     * @notice Get the current amount that can be received from the source endpoint id for the given rate limit window.
     * @param srcEid The source endpoint id.
     * @return currentAmountInFlight The current amount that has been received in this window.
     * @return amountCanBeReceived The amount that can be received.
     */
    function getAmountCanBeReceived(
        uint32 srcEid
    ) external view returns (uint256 currentAmountInFlight, uint256 amountCanBeReceived);
}
