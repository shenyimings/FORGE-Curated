// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../../lib/AggregatorV3Interface.sol";
import "v3-core/libraries/FullMath.sol";

/// @title Helper contract which allows to combine 2 chainlink feeds into 1 like wstETH/ETH and ETH/USD
contract ChainlinkFeedCombinator is AggregatorV3Interface {
  
    uint256 immutable firstDecimalsDivisor;
    uint8 immutable secondDecimals;
    AggregatorV3Interface immutable firstFeed;
    AggregatorV3Interface immutable secondFeed;

    constructor(AggregatorV3Interface first, AggregatorV3Interface second) {
        firstDecimalsDivisor = 10 ** first.decimals();
        secondDecimals = second.decimals();

        firstFeed = first;
        secondFeed = second;
    }

    function latestRoundData() external override view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        (uint80 firstRoundId, int256 firstAnswer,uint256 firstStartedAt, uint256 firstUpdatedAt, uint80 firstAnsweredInRound) = firstFeed.latestRoundData();
        int256 secondAnswer;
        (roundId, secondAnswer, startedAt, updatedAt, answeredInRound) = secondFeed.latestRoundData();

        // take oldest values - roundId and answeredInRound dont make much sense but will be returned from the corresponding feed (which has the older data)
        if (updatedAt > firstUpdatedAt) {
            roundId = firstRoundId;
            startedAt = firstStartedAt;
            updatedAt = firstUpdatedAt;
            answeredInRound = firstAnsweredInRound;
        }

        // only do calculation with valid values - otherwise returns 0
        if (firstAnswer > 0 && secondAnswer > 0) {
            answer = int256(FullMath.mulDiv(uint256(firstAnswer), uint256(secondAnswer), firstDecimalsDivisor));
        }
    }

    function decimals() external override view returns (uint8) {
        return secondDecimals;
    }
}
