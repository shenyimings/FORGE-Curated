// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockChainlinkFeed {
    struct LatestRoundData {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
    }

    LatestRoundData private _latestRoundData;
    uint8 public decimals;

    function setLatestRoundData(LatestRoundData memory __latestRoundData) external {
        _latestRoundData = __latestRoundData;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _latestRoundData.answer, 0, _latestRoundData.timestamp, 0);
    }

    function setDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }
}
