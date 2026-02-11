// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../../src/interfaces/aerodrome/IAerodromeSlipstreamPool.sol";

contract MockPool is IAerodromeSlipstreamPool {
    address public immutable override token0;
    address public immutable override token1;
    uint24 public immutable override fee;
    int24 public immutable override tickSpacing;
    
    uint160 public sqrtPriceX96;
    int24 public tick;
    uint16 public observationIndex;
    uint16 public observationCardinality;
    uint16 public observationCardinalityNext;
    bool public unlocked = true;
    
    uint256 public override feeGrowthGlobal0X128;
    uint256 public override feeGrowthGlobal1X128;
    
    constructor(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
        sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price
        tick = 0;
    }
    
    function slot0() external view override returns (
        uint160 sqrtPriceX96_,
        int24 tick_,
        uint16 observationIndex_,
        uint16 observationCardinality_,
        uint16 observationCardinalityNext_,
        bool unlocked_
    ) {
        return (
            sqrtPriceX96,
            tick,
            observationIndex,
            observationCardinality,
            observationCardinalityNext,
            unlocked
        );
    }
    
    function setSqrtPriceX96(uint160 _sqrtPriceX96) external {
        sqrtPriceX96 = _sqrtPriceX96;
    }
    
    function setTick(int24 _tick) external {
        tick = _tick;
    }
    
    // Implement required functions with minimal functionality
    function positions(bytes32) external pure override returns (
        uint128 _liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) {
        return (0, 0, 0, 0, 0);
    }
    
    function observations(uint256) external pure override returns (
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityPostWriteX128,
        bool initialized
    ) {
        return (0, 0, 0, false);
    }
    
    function observe(uint32[] calldata) external pure override returns (
        int56[] memory tickCumulatives,
        uint160[] memory secondsPerLiquidityPostWriteX128s
    ) {
        return (new int56[](0), new uint160[](0));
    }
    
    function ticks(int24) external pure override returns (
        uint128 liquidityGross,
        int128 liquidityNet,
        int128 stakedLiquidityNet,
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        uint256 rewardGrowthOutsideX128,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized
    ) {
        return (0, 0, 0, 0, 0, 0, 0, 0, 0, false);
    }
}