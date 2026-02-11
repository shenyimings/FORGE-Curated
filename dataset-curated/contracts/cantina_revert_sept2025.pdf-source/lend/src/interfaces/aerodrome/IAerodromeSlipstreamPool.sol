// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Aerodrome Slipstream Pool Interface
/// @notice Aerodrome's concentrated liquidity pool interface
/// @dev Aerodrome CLPool has a different slot0 structure than Uniswap V3
interface IAerodromeSlipstreamPool {
    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// @dev Aerodrome version: removed feeProtocol field compared to Uniswap V3
    /// @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
    /// @return tick The current tick of the pool
    /// @return observationIndex The index of the last oracle observation that was written
    /// @return observationCardinality The current maximum number of observations stored in the pool
    /// @return observationCardinalityNext The next maximum number of observations, to be updated when the observation
    /// @return unlocked Whether the pool is currently locked to reentrancy
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        );

    /// @notice The pool's fee in basis points
    /// @return The fee
    function fee() external view returns (uint24);

    /// @notice Returns the information about a position
    function positions(bytes32 key)
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    /// @notice Returns data about a specific observation index
    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityPostWriteX128,
            bool initialized
        );

    /// @notice Returns the cumulative tick and liquidity as of each timestamp `secondsAgo` from the current block timestamp
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityPostWriteX128s);

    /// @notice The pool tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice The first of the two tokens of the pool
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool
    function token1() external view returns (address);

    /// @notice The pool's fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool
    function feeGrowthGlobal0X128() external view returns (uint256);

    /// @notice The pool's fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool
    function feeGrowthGlobal1X128() external view returns (uint256);

    /// @notice Look up information about a specific tick in the pool
    /// @dev Aerodrome version includes stakedLiquidityNet and rewardGrowthOutsideX128
    function ticks(int24 tick)
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            int128 stakedLiquidityNet,  // Aerodrome addition
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            uint256 rewardGrowthOutsideX128,  // Aerodrome addition
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        );
}