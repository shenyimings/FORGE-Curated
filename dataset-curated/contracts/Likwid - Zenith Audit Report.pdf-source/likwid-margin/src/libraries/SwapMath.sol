// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Reserves} from "../types/Reserves.sol";
import {Math} from "./Math.sol";
import {FeeLibrary} from "./FeeLibrary.sol";
import {PerLibrary} from "./PerLibrary.sol";
import {FixedPoint96} from "./FixedPoint96.sol";
import {CustomRevert} from "./CustomRevert.sol";

library SwapMath {
    using CustomRevert for bytes4;
    using FeeLibrary for uint24;
    using PerLibrary for uint256;

    /// @notice The maximum swap fee in hundredths of a bip (1e6 = 100%).
    uint256 internal constant MAX_SWAP_FEE = 1e6;

    error InsufficientLiquidity();
    error InsufficientInputAmount();

    /**
     * @notice Calculates the absolute difference between two prices.
     * @param price The current price.
     * @param lastPrice The previous price.
     * @return priceDiff The absolute difference.
     */
    function differencePrice(uint256 price, uint256 lastPrice) internal pure returns (uint256 priceDiff) {
        priceDiff = price > lastPrice ? price - lastPrice : lastPrice - price;
    }

    /**
     * @notice Calculates the degree of price change caused by a swap, used for dynamic fee calculation.
     * @dev This function calculates price impact based on reserves and swap amounts.
     * @param pairReserves The current reserves of the pair.
     * @param truncatedReserves The reserves at the last fee calculation checkpoint.
     * @param lpFee The base liquidity provider fee.
     * @param zeroForOne The direction of the swap.
     * @param amountIn The amount of tokens being swapped in.
     * @param amountOut The amount of tokens being swapped out.
     * @return degree The calculated degree of price change.
     */
    function getPriceDegree(
        Reserves pairReserves,
        Reserves truncatedReserves,
        uint24 lpFee,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut
    ) internal pure returns (uint256 degree) {
        if (truncatedReserves.bothPositive()) {
            uint256 lastPrice0X96 = truncatedReserves.getPrice0X96();
            uint256 lastPrice1X96 = truncatedReserves.getPrice1X96();
            (uint256 _reserve0, uint256 _reserve1) = pairReserves.reserves();
            if (_reserve0 == 0 || _reserve1 == 0) {
                return degree;
            }
            if (amountIn > 0) {
                (amountOut,) = getAmountOut(pairReserves, lpFee, zeroForOne, amountIn);
            } else if (amountOut > 0) {
                (amountIn,) = getAmountIn(pairReserves, lpFee, zeroForOne, amountOut);
            }
            unchecked {
                if (zeroForOne) {
                    _reserve1 -= amountOut;
                    _reserve0 += amountIn;
                } else {
                    _reserve0 -= amountOut;
                    _reserve1 += amountIn;
                }
            }
            uint256 price0X96 = Math.mulDiv(_reserve1, FixedPoint96.Q96, _reserve0);
            uint256 price1X96 = Math.mulDiv(_reserve0, FixedPoint96.Q96, _reserve1);
            uint256 degree0 = differencePrice(price0X96, lastPrice0X96).mulMillionDiv(lastPrice0X96);
            uint256 degree1 = differencePrice(price1X96, lastPrice1X96).mulMillionDiv(lastPrice1X96);
            degree = Math.max(degree0, degree1);
        }
    }

    /**
     * @notice Calculates a dynamic fee based on the degree of price change.
     * @dev The fee increases with the price impact (degree).
     * @param swapFee The base swap fee.
     * @param degree The degree of price change.
     * @return _fee The calculated dynamic fee.
     */
    function dynamicFee(uint24 swapFee, uint256 degree) internal pure returns (uint24 _fee) {
        _fee = swapFee;
        if (degree > MAX_SWAP_FEE) {
            _fee = uint24(MAX_SWAP_FEE) - 10000;
        } else if (degree > 100000) {
            uint256 dFee = Math.mulDiv((degree * 10) ** 3, _fee, MAX_SWAP_FEE ** 3);
            if (dFee >= MAX_SWAP_FEE) {
                _fee = uint24(MAX_SWAP_FEE) - 10000;
            } else {
                _fee = uint24(dFee);
            }
        }
    }

    /**
     * @notice Calculates the output amount and fee for a given input amount and fixed fee.
     * @param pairReserves The reserves of the token pair.
     * @param lpFee The liquidity provider fee.
     * @param zeroForOne The direction of the swap.
     * @param amountIn The amount of input tokens.
     * @return amountOut The calculated amount of output tokens.
     * @return feeAmount The amount of fees paid.
     */
    function getAmountOut(Reserves pairReserves, uint24 lpFee, bool zeroForOne, uint256 amountIn)
        internal
        pure
        returns (uint256 amountOut, uint256 feeAmount)
    {
        if (amountIn == 0) InsufficientInputAmount.selector.revertWith();
        (uint128 _reserve0, uint128 _reserve1) = pairReserves.reserves();
        (uint256 reserveIn, uint256 reserveOut) = zeroForOne ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        if (reserveIn == 0 || reserveOut == 0) InsufficientLiquidity.selector.revertWith();
        uint256 amountInWithoutFee;
        (amountInWithoutFee, feeAmount) = lpFee.deduct(amountIn);
        uint256 numerator = amountInWithoutFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithoutFee;
        amountOut = numerator / denominator;
    }

    /**
     * @notice Calculates the output amount using a dynamic fee based on price impact.
     * @param pairReserves The current reserves of the pair.
     * @param truncatedReserves The reserves at the last fee calculation checkpoint.
     * @param lpFee The base liquidity provider fee.
     * @param zeroForOne The direction of the swap.
     * @param amountIn The amount of input tokens.
     * @return amountOut The calculated amount of output tokens.
     * @return fee The dynamic fee applied.
     * @return feeAmount The amount of fees paid.
     */
    function getAmountOut(
        Reserves pairReserves,
        Reserves truncatedReserves,
        uint24 lpFee,
        bool zeroForOne,
        uint256 amountIn
    ) internal pure returns (uint256 amountOut, uint24 fee, uint256 feeAmount) {
        uint256 degree = getPriceDegree(pairReserves, truncatedReserves, lpFee, zeroForOne, amountIn, 0);
        fee = dynamicFee(lpFee, degree);
        (amountOut, feeAmount) = getAmountOut(pairReserves, fee, zeroForOne, amountIn);
    }

    /**
     * @notice Calculates the required input amount and fee for a given output amount and fixed fee.
     * @param pairReserves The reserves of the token pair.
     * @param lpFee The liquidity provider fee.
     * @param zeroForOne The direction of the swap.
     * @param amountOut The desired amount of output tokens.
     * @return amountIn The required amount of input tokens.
     * @return feeAmount The amount of fees paid from the input tokens.
     */
    function getAmountIn(Reserves pairReserves, uint24 lpFee, bool zeroForOne, uint256 amountOut)
        internal
        pure
        returns (uint256 amountIn, uint256 feeAmount)
    {
        (uint128 _reserve0, uint128 _reserve1) = pairReserves.reserves();
        (uint256 reserveIn, uint256 reserveOut) = zeroForOne ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        if (reserveIn == 0 || reserveOut == 0) InsufficientLiquidity.selector.revertWith();
        if (amountOut >= reserveOut) InsufficientLiquidity.selector.revertWith();

        uint256 amountInWithoutFee = Math.mulDiv(reserveIn, amountOut, reserveOut - amountOut) + 1;

        uint256 numerator = amountInWithoutFee * MAX_SWAP_FEE;
        uint256 denominator = MAX_SWAP_FEE - lpFee;
        amountIn = (numerator + denominator - 1) / denominator;
        feeAmount = amountIn - amountInWithoutFee;
    }

    /**
     * @notice Calculates the required input amount using a dynamic fee based on price impact.
     * @param pairReserves The current reserves of the pair.
     * @param truncatedReserves The reserves at the last fee calculation checkpoint.
     * @param lpFee The base liquidity provider fee.
     * @param zeroForOne The direction of the swap.
     * @param amountOut The desired amount of output tokens.
     * @return amountIn The required amount of input tokens.
     * @return fee The dynamic fee applied.
     * @return feeAmount The amount of fees paid.
     */
    function getAmountIn(
        Reserves pairReserves,
        Reserves truncatedReserves,
        uint24 lpFee,
        bool zeroForOne,
        uint256 amountOut
    ) internal pure returns (uint256 amountIn, uint24 fee, uint256 feeAmount) {
        (uint256 approxAmountIn,) = getAmountIn(pairReserves, lpFee, zeroForOne, amountOut);
        uint256 degree = getPriceDegree(pairReserves, truncatedReserves, lpFee, zeroForOne, approxAmountIn, amountOut);
        fee = dynamicFee(lpFee, degree);
        (amountIn, feeAmount) = getAmountIn(pairReserves, fee, zeroForOne, amountOut);
    }
}
