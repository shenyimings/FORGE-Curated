// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract MockChainlinkPriceFeed {
    uint8 private _decimals;
    int256 private _latestAnswer;
    uint256 private _staleness;

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setLatestAnswer(int256 answer) external {
        _latestAnswer = answer;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestAnswer() external view returns (int256) {
        return _latestAnswer;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _latestAnswer, 0, block.timestamp - _staleness, 0);
    }

    function setMockPriceStaleness(uint256 staleness) external {
        _staleness = staleness;
    }
}
