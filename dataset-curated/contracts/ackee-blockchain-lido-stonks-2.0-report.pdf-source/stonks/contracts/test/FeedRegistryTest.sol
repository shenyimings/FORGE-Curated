// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IFeedRegistry} from "../interfaces/IFeedRegistry.sol";

/**
 * @title Test contract for FeedRegistry functionality.
 */
contract FeedRegistryTest {
    // ==================== Immutables ====================

    /// @notice Address of the Chainlink Feed Registry contract.
    address public immutable FEED_REGISTRY;

    // ==================== Storage Variables ====================

    /// @notice Heartbeat timeout used for testing stale feed scenarios.
    uint256 public heartbeat;

    // ==================== Constructor ====================

    /**
     * @notice Initializes the test contract.
     * @param feedRegistry_ Feed registry address.
     */
    constructor(address feedRegistry_) {
        FEED_REGISTRY = feedRegistry_;
    }

    // ==================== External Functions ====================

    /**
     * @notice Sets the heartbeat timeout for testing.
     * @param heartbeat_ Heartbeat value in seconds.
     */
    function setHeartbeat(uint256 heartbeat_) external {
        heartbeat = heartbeat_;
    }

    // ==================== External View Functions ====================

    /**
     * @notice Gets the feed aggregator address.
     * @param base Base token address.
     * @param quote Quote token address.
     * @return Aggregator address.
     */
    function getFeed(address base, address quote) external view returns (address) {
        return IFeedRegistry(FEED_REGISTRY).getFeed(base, quote);
    }

    /**
     * @notice Gets the feed decimals.
     * @param base Base token address.
     * @param quote Quote token address.
     * @return Decimals value.
     */
    function decimals(address base, address quote) external view returns (uint8) {
        return IFeedRegistry(FEED_REGISTRY).decimals(base, quote);
    }

    /**
     * @notice Gets the latest round data, optionally adjusting updatedAt timestamp.
     * @param base Base token address.
     * @param quote Quote token address.
     * @return roundId Round ID.
     * @return answer Price answer.
     * @return startedAt Timestamp when round started.
     * @return updatedAt Timestamp when round was updated (adjusted if heartbeat is set).
     * @return answeredInRound Round ID in which answer was computed.
     */
    function latestRoundData(
        address base,
        address quote
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = IFeedRegistry(FEED_REGISTRY)
            .latestRoundData(base, quote);

        if (heartbeat != 0) {
            updatedAt = block.timestamp - heartbeat;
        }
    }
}
