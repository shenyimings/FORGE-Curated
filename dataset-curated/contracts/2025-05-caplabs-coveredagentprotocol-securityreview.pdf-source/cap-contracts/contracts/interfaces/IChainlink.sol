// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title Chainlink Interface
/// @author @capLabs
/// @notice Interface for Chainlink price feeds
interface IChainlink {
    /// @notice Get the number of decimals of the price feed
    /// @return decimals Number of decimals of the price feed
    function decimals() external view returns (uint8);
    /// @notice Get the latest price of the price feed
    /// @return price Latest price of the price feed
    function latestAnswer() external view returns (int256);
    /// @notice Get the latest round data of the price feed
    /// @return roundId Round ID of the price feed
    /// @return answer Price of the price feed
    /// @return startedAt Timestamp of the price feed
    /// @return updatedAt Timestamp of the price feed
    /// @return answeredInRound Round ID of the price feed
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}
