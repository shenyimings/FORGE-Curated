// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Interface for Chainlink Aggregator
interface IAggregatorV2V3Interface {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (int256);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
