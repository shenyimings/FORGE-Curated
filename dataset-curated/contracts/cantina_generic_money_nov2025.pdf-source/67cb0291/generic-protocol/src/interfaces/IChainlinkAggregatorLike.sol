// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IChainlinkAggregatorLike
 * @notice Interface for interacting with Chainlink price feed aggregators
 * @dev This interface provides a simplified view of Chainlink aggregator contracts,
 * focusing on the essential functions needed for price data retrieval.
 * It follows the Chainlink AggregatorV3Interface pattern but with a reduced surface area.
 */
interface IChainlinkAggregatorLike {
    /**
     * @notice Returns the number of decimals the aggregator responses represent
     * @return The number of decimals for the price data (e.g., 8 for USD pairs, 18 for ETH pairs)
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns detailed data for the latest round of price updates
     * @dev This function provides comprehensive information about the latest price round,
     * including timestamps and round identifiers. It is useful for verifying the freshness
     * and reliability of the price data.
     * @return roundId The identifier for the latest round
     * @return answer The latest price as a signed integer
     * @return startedAt The timestamp when the round started
     * @return updatedAt The timestamp when the round was last updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
