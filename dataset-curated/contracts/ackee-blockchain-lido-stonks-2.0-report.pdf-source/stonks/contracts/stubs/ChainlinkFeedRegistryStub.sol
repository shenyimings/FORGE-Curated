// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IFeedRegistry} from "../interfaces/IFeedRegistry.sol";
import {ManageableStub} from "./ManageableStub.sol";

/**
 * @title Stub for the Chainlink's Feed Registry contract
 * @notice Contract is supposed to be used with the AmountConverter contract
 *     to return preset answers.
 */
contract ChainlinkFeedRegistryStub is IFeedRegistry, ManageableStub {
    // ==================== Type Definitions ====================

    struct FeedStub {
        address aggregator;
        uint80 roundId;
        uint80 answeredInRound;
        uint8 decimals;
        uint256 startedAt;
        uint256 updatedAt;
        int256 answer;
    }

    // ==================== Storage Variables ====================

    /// @notice Mapping from base/quote token pair to feed data.
    mapping(address base => mapping(address quote => FeedStub feed)) public feeds;

    // ==================== Events ====================

    event FeedSet(address base, address quote, FeedStub feed);

    // ==================== Constructor ====================

    constructor(address owner_, address manager_) ManageableStub(owner_, manager_) {}

    // ==================== External View Functions ====================

    /**
     * @notice Gets the aggregator address for a given base/quote pair.
     * @param base Base token address.
     * @param quote Quote token address.
     * @return Aggregator address.
     */
    function getFeed(address base, address quote) external view returns (address) {
        return feeds[base][quote].aggregator;
    }

    /**
     * @notice Gets the decimals for a given base/quote pair.
     * @param base Base token address.
     * @param quote Quote token address.
     * @return Decimals value.
     */
    function decimals(address base, address quote) external view returns (uint8) {
        return feeds[base][quote].decimals;
    }

    /**
     * @notice Gets the latest round data for a given base/quote pair.
     * @param base Base token address.
     * @param quote Quote token address.
     * @return roundId Round ID.
     * @return answer Price answer.
     * @return startedAt Timestamp when round started.
     * @return updatedAt Timestamp when round was updated.
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
        FeedStub memory feed = feeds[base][quote];

        answer = feed.answer;
        roundId = feed.roundId;
        answeredInRound = feed.answeredInRound;

        if (feed.startedAt == 0) {
            startedAt = block.timestamp;
        } else {
            startedAt = feed.startedAt;
        }

        if (feed.updatedAt == 0) {
            updatedAt = block.timestamp;
        } else {
            updatedAt = feed.updatedAt;
        }
    }

    // ==================== External Functions ====================

    /**
     * @notice Sets the feed data for a given base/quote pair.
     * @param base Base token address.
     * @param quote Quote token address.
     * @param feed Feed data structure.
     */
    function setFeed(address base, address quote, FeedStub calldata feed) external {
        feeds[base][quote] = feed;

        emit FeedSet(base, quote, feed);
    }
}
