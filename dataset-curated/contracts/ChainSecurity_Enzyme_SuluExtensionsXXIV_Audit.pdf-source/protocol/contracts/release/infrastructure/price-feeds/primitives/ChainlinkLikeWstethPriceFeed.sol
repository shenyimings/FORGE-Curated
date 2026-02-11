// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

import {IChainlinkAggregator} from "../../../../external-interfaces/IChainlinkAggregator.sol";
import {ILidoSteth} from "../../../../external-interfaces/ILidoSteth.sol";

/// @title ChainlinkLikeWstethPriceFeed Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Price feed for Lido wrapped stETH (wstETH), wrapped in a Chainlink-like interface and quoted in ETH
/// @dev Relies on a stETH/ETH feed with the Chainlink aggregator interface for the intermediary conversion step
contract ChainlinkLikeWstethPriceFeed is IChainlinkAggregator {
    uint8 private constant CHAINLINK_AGGREGATOR_ETH_QUOTE_DECIMALS = 18;
    uint256 private constant STETH_UNIT = 10 ** 18;
    uint256 private constant WSTETH_UNIT = 10 ** 18;

    ILidoSteth private immutable STETH;
    IChainlinkAggregator private immutable STETH_ETH_CHAINLINK_AGGREGATOR;

    error ChainlinkLikeWstethPriceFeed__NegativeAnswer();

    constructor(ILidoSteth _steth, IChainlinkAggregator _stethEthChainlinkAggregator) {
        STETH = _steth;
        STETH_ETH_CHAINLINK_AGGREGATOR = _stethEthChainlinkAggregator;
    }

    /// @notice The number of precision decimals in the aggregator answer
    /// @return decimals_ The number of decimals
    function decimals() external pure override returns (uint8 decimals_) {
        return CHAINLINK_AGGREGATOR_ETH_QUOTE_DECIMALS;
    }

    /// @notice Returns Chainlink-like latest round data for the wstETH/ETH pair
    /// @return roundId_ Unused
    /// @return answer_ The price of wstETH quoted in ETH
    /// @return startedAt_ The `startedAt_` value returned by the Chainlink stETH/ETH aggregator `latestRoundData()`
    /// @return updatedAt_ The `updatedAt_` value returned by the Chainlink stETH/ETH aggregator `latestRoundData()`
    /// @return answeredInRound_ Unused
    /// @dev Does not pass through round-related values, to avoid misinterpretation
    function latestRoundData()
        external
        view
        override
        returns (uint80, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80)
    {
        // steth-per-wsteth rate
        uint256 stethPerWsteth = STETH.getPooledEthByShares({_sharesAmount: WSTETH_UNIT});

        // eth-per-steth rate
        int256 ethPerStethAnswer;
        (, ethPerStethAnswer, startedAt_, updatedAt_,) = STETH_ETH_CHAINLINK_AGGREGATOR.latestRoundData();

        if (ethPerStethAnswer < 0) {
            revert ChainlinkLikeWstethPriceFeed__NegativeAnswer();
        }

        // eth-per-wsteth rate
        answer_ = int256(uint256(ethPerStethAnswer) * stethPerWsteth / STETH_UNIT);

        return (uint80(0), answer_, startedAt_, updatedAt_, uint80(0));
    }
}
