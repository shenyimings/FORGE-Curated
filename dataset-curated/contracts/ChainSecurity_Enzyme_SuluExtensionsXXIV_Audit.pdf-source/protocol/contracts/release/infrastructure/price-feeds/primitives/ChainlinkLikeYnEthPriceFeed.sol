// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

import {IChainlinkAggregator} from "../../../../external-interfaces/IChainlinkAggregator.sol";
import {ICurveV2TwocryptoPool} from "../../../../external-interfaces/ICurveV2TwocryptoPool.sol";

/// @title ChainlinkLikeYnEthPriceFeed Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Price feed for Yield Nest ETH (ynETH), wrapped in a Chainlink-like interface and quoted in ETH
/// @dev The rate calculation relies on (and inherits the risks of):
/// 1. a Chainlink-like aggregator for wstETH/ETH
/// 2. a Curve Twocrypto pool's internal EMA oracle for ynETH-wstETH
/// This contract's aggregator timestamp (i.e., freshness) is inherited from (1), and (2) is not checked.
/// In the Curve pool used, ynETH must be the pool member at index 0 (`coins(0)`).
contract ChainlinkLikeYnEthPriceFeed is IChainlinkAggregator {
    uint8 private constant CHAINLINK_AGGREGATOR_ETH_QUOTE_DECIMALS = 18;
    uint256 private constant WSTETH_UNIT = 10 ** 18;

    ICurveV2TwocryptoPool private immutable CURVE_YNETH_WSTETH_POOL;
    IChainlinkAggregator private immutable WSTETH_ETH_CHAINLINK_AGGREGATOR;

    error ChainlinkLikeYnEthPriceFeed__NegativeAnswer();

    constructor(ICurveV2TwocryptoPool _curveYnethWstethPool, IChainlinkAggregator _wstethEthChainlinkAggregator) {
        CURVE_YNETH_WSTETH_POOL = _curveYnethWstethPool;
        WSTETH_ETH_CHAINLINK_AGGREGATOR = _wstethEthChainlinkAggregator;
    }

    /// @notice The number of precision decimals in the aggregator answer
    /// @return decimals_ The number of decimals
    function decimals() external pure override returns (uint8 decimals_) {
        return CHAINLINK_AGGREGATOR_ETH_QUOTE_DECIMALS;
    }

    /// @notice Returns Chainlink-like latest round data for the derivative asset
    /// @return roundId_ Unused
    /// @return answer_ The price of the derivative asset quoted in ETH
    /// @return startedAt_ The `startedAt_` value returned by the wstETH/ETH aggregator `latestRoundData()`
    /// @return updatedAt_ The `updatedAt_` value returned by the wstETH/ETH aggregator `latestRoundData()`
    /// @return answeredInRound_ Unused
    /// @dev Does not pass through round-related values, to avoid misinterpretation.
    /// Does not check the rate timestamp of the ynETH-wstETH Curve pool. This rate is assumed to be up-to-date,
    /// since if the market rate changes, pool balances will be arbitraged to correct it, refreshing the rate timestamp.
    function latestRoundData()
        external
        view
        override
        returns (uint80, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80)
    {
        // yneth-per-wsteth rate
        // Source: Curve pool internal EMA oracle
        uint256 ynEthPerWsteth = CURVE_YNETH_WSTETH_POOL.price_oracle();

        // eth-per-wsteth rate
        // Source: Chainlink-like aggregator
        int256 ethPerWstethAnswer;
        (, ethPerWstethAnswer, startedAt_, updatedAt_,) = WSTETH_ETH_CHAINLINK_AGGREGATOR.latestRoundData();

        if (ethPerWstethAnswer < 0) {
            revert ChainlinkLikeYnEthPriceFeed__NegativeAnswer();
        }

        // eth-per-yneth rate
        answer_ = int256(uint256(ethPerWstethAnswer) * WSTETH_UNIT / ynEthPerWsteth);

        return (uint80(0), answer_, startedAt_, updatedAt_, uint80(0));
    }
}
