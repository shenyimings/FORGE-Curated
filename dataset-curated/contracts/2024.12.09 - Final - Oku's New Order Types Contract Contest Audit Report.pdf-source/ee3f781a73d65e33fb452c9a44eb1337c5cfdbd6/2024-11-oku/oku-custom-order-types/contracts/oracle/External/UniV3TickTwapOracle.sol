// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../IOracleRelay.sol";
import "../uniswap/IUniswapV3PoolDerivedState.sol";
import "../uniswap/TickMath.sol";

/// @title Oracle that wraps a univ3 pool
/// @notice The oracle returns the twap price as the current tick
/// if quote_token_is_token0 == true, then the reciprocal is returned
contract UniV3TickTwapOracle is IOracleRelay {
    IUniswapV3PoolDerivedState public immutable pool;
    uint32 public immutable lookback;
    address public immutable underlying;

    /// @notice all values set at construction time
    /// @param _lookback how many seconds to twap for
    /// @param  _pool_address address of the pool twap applies to
    constructor(uint32 _lookback, IUniswapV3PoolDerivedState _pool_address) {
        lookback = _lookback;
        pool = _pool_address;
        underlying = address(pool);
    }

    function currentValue() external view override returns (uint256) {
        return uint256(uint24(getLastSeconds(lookback)));
    }

    function getLastSeconds(uint32 _seconds) private view returns (int24 tick) {
        int56[] memory tickCumulatives;
        uint32[] memory input = new uint32[](2);
        input[0] = _seconds;
        input[1] = 0;

        (tickCumulatives, ) = pool.observe(input);

        uint32 tickTimeDifference = _seconds;
        int56 tickCumulativeDifference = tickCumulatives[0] -
            tickCumulatives[1];
        bool tickNegative = tickCumulativeDifference < 0;
        uint56 tickAbs;
        if (tickNegative) {
            tickAbs = uint56(-tickCumulativeDifference);
        } else {
            tickAbs = uint56(tickCumulativeDifference);
        }

        uint56 bigTick = tickAbs / tickTimeDifference;
        require(bigTick < 887272, "Tick time diff fail");
        if (tickNegative) {
            tick = -int24(int56(bigTick));
        } else {
            tick = int24(int56(bigTick));
        }
    }
}
