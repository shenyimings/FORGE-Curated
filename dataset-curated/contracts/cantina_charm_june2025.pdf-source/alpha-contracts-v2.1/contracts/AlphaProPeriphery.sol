// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "../interfaces/IVault.sol";

struct PositionAmounts {
    uint256 amount0;
    uint256 amount1;
    uint256 fees0;
    uint256 fees1;
    uint256 total0;
    uint256 total1;
}

struct CalculateFeesParams {
    uint256 feeGrowthInsideLast;
    uint256 feeGrowthOutsideLower;
    uint256 feeGrowthOutsideUpper;
    uint256 feeGrowthGlobal;
    uint128 liquidity;
    int24 tick;
    int24 lowerTick;
    int24 upperTick;
    uint256 performanceFee; // Protocol + manager fees
}

struct GetFeesParams {
    int24 lowerTick;
    int24 upperTick;
    address poolAddress;
    address vaultAddress;
    uint256 performanceFee;
}

contract AlphaProPeriphery {
    // Get vault positions and balance
    function getVaultPositions(address vaultAddress)
        public
        view
        returns (PositionAmounts[3] memory results, uint256 balance0, uint256 balance1)
    {
        IVault vault = IVault(vaultAddress);
        address pool = address(vault.pool());

        GetFeesParams memory getFeesParams = GetFeesParams(
            vault.wideLower(), vault.wideUpper(), pool, vaultAddress, vault.managerFee() + vault.protocolFee()
        );
        results[0] = getFees(getFeesParams);

        (getFeesParams.lowerTick, getFeesParams.upperTick) = (vault.baseLower(), vault.baseUpper());
        results[1] = getFees(getFeesParams);

        (getFeesParams.lowerTick, getFeesParams.upperTick) = (vault.limitLower(), vault.limitUpper());
        results[2] = getFees(getFeesParams);

        (balance0, balance1) = (vault.getBalance0(), vault.getBalance1());
    }

    // Get fees for a specific position
    function getFees(GetFeesParams memory params) public view returns (PositionAmounts memory positionAmounts) {
        IUniswapV3Pool pool = IUniswapV3Pool(params.poolAddress);
        (uint160 sqrtRatioX96, int24 tick,,,,,) = pool.slot0();
        bytes32 positionKey = PositionKey.compute(params.vaultAddress, params.lowerTick, params.upperTick);
        (uint128 liquidity, uint256 feeGrowthInside0Last, uint256 feeGrowthInside1Last,,) = pool.positions(positionKey);
        (,, uint256 feeGrowthOutside0Lower, uint256 feeGrowthOutside1Lower,,,,) = pool.ticks(params.lowerTick);
        (,, uint256 feeGrowthOutside0Upper, uint256 feeGrowthOutside1Upper,,,,) = pool.ticks(params.upperTick);

        CalculateFeesParams memory calcParams = CalculateFeesParams({
            feeGrowthGlobal: pool.feeGrowthGlobal0X128(),
            feeGrowthInsideLast: feeGrowthInside0Last,
            feeGrowthOutsideLower: feeGrowthOutside0Lower,
            feeGrowthOutsideUpper: feeGrowthOutside0Upper,
            liquidity: liquidity,
            tick: tick,
            lowerTick: params.lowerTick,
            upperTick: params.upperTick,
            performanceFee: params.performanceFee
        });

        positionAmounts.fees0 = calculateFees(calcParams);

        (
            calcParams.feeGrowthGlobal,
            calcParams.feeGrowthInsideLast,
            calcParams.feeGrowthOutsideLower,
            calcParams.feeGrowthOutsideUpper
        ) = (pool.feeGrowthGlobal1X128(), feeGrowthInside1Last, feeGrowthOutside1Lower, feeGrowthOutside1Upper);
        positionAmounts.fees1 = calculateFees(calcParams);

        (positionAmounts.amount0, positionAmounts.amount1) =
            _amountsForLiquidity(params.lowerTick, params.upperTick, liquidity, sqrtRatioX96);

        positionAmounts.total0 = positionAmounts.amount0 + positionAmounts.fees0;
        positionAmounts.total1 = positionAmounts.amount1 + positionAmounts.fees1;
    }

    // Calculate fees for a specific position
    function calculateFees(CalculateFeesParams memory params) public pure returns (uint256 res) {
        uint256 feeGrowthBelow = params.tick >= params.lowerTick
            ? params.feeGrowthOutsideLower
            : params.feeGrowthGlobal - params.feeGrowthOutsideLower;
        uint256 feeGrowthAbove = params.tick < params.upperTick
            ? params.feeGrowthOutsideUpper
            : params.feeGrowthGlobal - params.feeGrowthOutsideUpper;

        res = Math.mulDiv(
            params.liquidity,
            params.feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove - params.feeGrowthInsideLast,
            0x100000000000000000000000000000000
        );

        // Subtract protocol and manager fee
        res -= Math.mulDiv(res, params.performanceFee, 1e6);
    }

    // Calculate amounts for liquidity based on the given ticks and liquidity value
    function _amountsForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity, uint160 sqrtRatioX96)
        internal
        pure
        returns (uint256, uint256)
    {
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }
}
