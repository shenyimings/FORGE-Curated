// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IChainlink } from "../../interfaces/IChainlink.sol";

/// @title Chainlink Adapter
/// @author kexley, @capLabs
/// @notice Prices are sourced from Chainlink
library ChainlinkAdapter {
    /// @notice Fetch price for an asset from Chainlink fixed to 8 decimals
    /// @param _source Chainlink aggregator
    /// @return latestAnswer Price of the asset fixed to 8 decimals
    /// @return lastUpdated Latest timestamp of the price
    function price(address _source) external view returns (uint256 latestAnswer, uint256 lastUpdated) {
        uint8 decimals = IChainlink(_source).decimals();
        int256 intLatestAnswer;
        (, intLatestAnswer,, lastUpdated,) = IChainlink(_source).latestRoundData();
        latestAnswer = uint256(intLatestAnswer);
        if (decimals < 8) latestAnswer *= 10 ** (8 - decimals);
        if (decimals > 8) latestAnswer /= 10 ** (decimals - 8);
    }
}
