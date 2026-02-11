// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniV4, IPoolManager} from "../interfaces/IUniV4.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {MixedSignLib} from "../libraries/MixedSignLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {TickIteratorUp, TickIteratorDown} from "./TickIterator.sol";
import {Math512Lib} from "./Math512Lib.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";
import {Q96MathLib} from "./Q96MathLib.sol";

/// @author philogy <https://github.com/philogy>
library CompensationPriceFinder {
    using IUniV4 for IPoolManager;
    using MixedSignLib for *;
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;
    using Q96MathLib for uint256;

    function getZeroForOne(
        TickIteratorDown memory ticks,
        uint128 liquidity,
        uint256 taxInEther,
        uint160 priceUpperSqrtX96,
        Slot0 slot0AfterSwap
    ) internal view returns (int24 lastTick, uint160 pstarSqrtX96) {
        uint256 sumAmount0Deltas = 0; // X
        uint256 sumAmount1Deltas = 0; // Y

        uint160 priceLowerSqrtX96;
        while (ticks.hasNext()) {
            lastTick = ticks.getNext();
            priceLowerSqrtX96 = TickMath.getSqrtPriceAtTick(lastTick);

            {
                uint256 delta0 = SqrtPriceMath.getAmount0Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                uint256 delta1 = SqrtPriceMath.getAmount1Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                sumAmount0Deltas += delta0;
                sumAmount1Deltas += delta1;

                if (sumAmount0Deltas > taxInEther) {
                    if (
                        sumAmount1Deltas.divX96(sumAmount0Deltas + taxInEther)
                            >= uint256(priceLowerSqrtX96).mulX96(priceLowerSqrtX96)
                    ) {
                        pstarSqrtX96 = _zeroForOneGetFinalCompensationPrice(
                            priceUpperSqrtX96,
                            taxInEther,
                            liquidity,
                            sumAmount0Deltas - delta0,
                            sumAmount1Deltas - delta1
                        );

                        return (lastTick, pstarSqrtX96);
                    }
                }
            }

            (, int128 liquidityNet) = ticks.manager.getTickLiquidity(ticks.poolId, lastTick);
            liquidity = liquidity.sub(liquidityNet);

            priceUpperSqrtX96 = priceLowerSqrtX96;
        }

        priceLowerSqrtX96 = slot0AfterSwap.sqrtPriceX96();

        uint256 delta0 =
            SqrtPriceMath.getAmount0Delta(priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false);
        uint256 delta1 =
            SqrtPriceMath.getAmount1Delta(priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false);
        sumAmount0Deltas += delta0;
        sumAmount1Deltas += delta1;

        uint256 simplePstarX96 = sumAmount1Deltas.divX96(sumAmount0Deltas + taxInEther);
        if (simplePstarX96 > uint256(priceLowerSqrtX96).mulX96(priceLowerSqrtX96)) {
            pstarSqrtX96 = _zeroForOneGetFinalCompensationPrice(
                priceUpperSqrtX96,
                taxInEther,
                liquidity,
                sumAmount0Deltas - delta0,
                sumAmount1Deltas - delta1
            );

            return (type(int24).min, pstarSqrtX96);
        }

        (uint256 p1, uint256 p0) = Math512Lib.checkedMul2Pow96(0, simplePstarX96);

        return (type(int24).min, Math512Lib.sqrt512(p1, p0).toUint160());
    }

    /// @dev Computes the effective execution price `p*` such that we can compensate as many
    /// liquidity ranges for the difference between their actual execution price and `p*`.
    function getOneForZero(
        TickIteratorUp memory ticks,
        uint128 liquidity,
        uint256 taxInEther,
        Slot0 slot0BeforeSwap,
        Slot0 slot0AfterSwap
    ) internal view returns (int24 lastTick, uint160 pstarSqrtX96) {
        uint256 sumAmount0Deltas = 0; // X
        uint256 sumAmount1Deltas = 0; // Y

        uint160 priceLowerSqrtX96 = slot0BeforeSwap.sqrtPriceX96();
        uint160 priceUpperSqrtX96;
        while (ticks.hasNext()) {
            lastTick = ticks.getNext();
            priceUpperSqrtX96 = TickMath.getSqrtPriceAtTick(lastTick);

            {
                uint256 delta0 = SqrtPriceMath.getAmount0Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                uint256 delta1 = SqrtPriceMath.getAmount1Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                sumAmount0Deltas += delta0;
                sumAmount1Deltas += delta1;

                if (sumAmount0Deltas > taxInEther) {
                    uint256 simplePstarX96 = sumAmount1Deltas.divX96(sumAmount0Deltas - taxInEther);
                    if (simplePstarX96 <= uint256(priceUpperSqrtX96).mulX96(priceUpperSqrtX96)) {
                        pstarSqrtX96 = _oneForZeroGetFinalCompensationPrice(
                            liquidity,
                            priceLowerSqrtX96,
                            taxInEther,
                            sumAmount0Deltas - delta0,
                            sumAmount1Deltas - delta1
                        );

                        return (lastTick, pstarSqrtX96);
                    }
                }
            }

            (, int128 liquidityNet) = ticks.manager.getTickLiquidity(ticks.poolId, lastTick);
            liquidity = liquidity.add(liquidityNet);

            priceLowerSqrtX96 = priceUpperSqrtX96;
        }

        priceUpperSqrtX96 = slot0AfterSwap.sqrtPriceX96();

        uint256 delta0 =
            SqrtPriceMath.getAmount0Delta(priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false);
        uint256 delta1 =
            SqrtPriceMath.getAmount1Delta(priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false);
        sumAmount0Deltas += delta0;
        sumAmount1Deltas += delta1;

        uint256 simplePstarX96 = sumAmount1Deltas.divX96(sumAmount0Deltas - taxInEther);
        if (simplePstarX96 <= uint256(priceUpperSqrtX96).mulX96(priceUpperSqrtX96)) {
            pstarSqrtX96 = _oneForZeroGetFinalCompensationPrice(
                liquidity,
                priceLowerSqrtX96,
                taxInEther,
                sumAmount0Deltas - delta0,
                sumAmount1Deltas - delta1
            );

            return (type(int24).max, pstarSqrtX96);
        }

        (uint256 p1, uint256 p0) = Math512Lib.checkedMul2Pow96(0, simplePstarX96);

        return (type(int24).max, Math512Lib.sqrt512(p1, p0).toUint160());
    }

    function _zeroForOneGetFinalCompensationPrice(
        uint160 priceUpperSqrtX96,
        uint256 compensationAmount0,
        uint128 liquidity,
        uint256 sumUpToThisRange0,
        uint256 sumUpToThisRange1
    ) internal pure returns (uint160 pstarSqrtX96) {
        uint256 rangeVirtualReserves0 = uint256(liquidity).divX96(priceUpperSqrtX96);
        uint256 rangeVirtualReserves1 = uint256(liquidity).mulX96(priceUpperSqrtX96);
        // sumX: `Xhat + B`
        uint256 sumX = sumUpToThisRange0 + compensationAmount0;
        (uint256 d1, uint256 d0) = Math512Lib.fullMul(rangeVirtualReserves1, sumX);
        if (sumX >= rangeVirtualReserves0) {
            // `A` is positive, compute `D = y * (Xhat + B) + A * Yhat`, `p* = (-L + sqrt(D)) / A`.
            uint256 a = sumX - rangeVirtualReserves0;
            {
                (uint256 ay1, uint256 ay0) = Math512Lib.fullMul(a, sumUpToThisRange1);
                (d1, d0) = Math512Lib.checkedAdd(d1, d0, ay1, ay0);
            }
            // Compute `sqrtDX96 := sqrt(D) * 2^96 <> sqrt(D * 2^192)`
            (d1, d0) = Math512Lib.checkedMul2Pow192(d1, d0);
            // Reuse `d1, d0` to store numerator `-L + sqrt(D)`.
            (d1, d0) =
                Math512Lib.checkedSub(0, Math512Lib.sqrt512(d1, d0), 0, uint256(liquidity) << 96);
            (uint256 upperBits, uint256 p1) = Math512Lib.div512by256(d1, d0, a);
            assert(upperBits == 0);

            return p1.toUint160();
        } else {
            // `A` is negative, compute `D = y * (Xhat + B) - (-A) * Yhat`, `p* = (L - sqrt(D)) / -A`.
            uint256 negA = rangeVirtualReserves0 - sumX;
            {
                (uint256 ay1, uint256 ay0) = Math512Lib.fullMul(negA, sumUpToThisRange1);
                (d1, d0) = Math512Lib.checkedSub(d1, d0, ay1, ay0);
            }
            // Compute `sqrtDX96 := sqrt(D) * 2^96 <> sqrt(D * 2^192)`
            (d1, d0) = Math512Lib.checkedMul2Pow192(d1, d0);
            // Reuse `d1, d0` to store numerator `L - sqrt(D)`.
            (d1, d0) =
                Math512Lib.checkedSub(0, uint256(liquidity) << 96, 0, Math512Lib.sqrt512(d1, d0));
            (uint256 upperBits, uint256 p1) = Math512Lib.div512by256(d1, d0, negA);
            assert(upperBits == 0);

            return p1.toUint160();
        }
    }

    function _oneForZeroGetFinalCompensationPrice(
        uint128 liquidity,
        uint160 priceLowerSqrtX96,
        uint256 compensationAmount0,
        uint256 sumUpToThisRange0,
        uint256 sumUpToThisRange1
    ) internal pure returns (uint160 pstarSqrtX96) {
        uint256 rangeVirtualReserves0 = uint256(liquidity).divX96(priceLowerSqrtX96);
        uint256 rangeVirtualReserves1 = uint256(liquidity).mulX96(priceLowerSqrtX96);
        // `A = Xhat + x - B`
        uint256 a = sumUpToThisRange0 + rangeVirtualReserves0 - compensationAmount0;
        // Compute determinant.
        uint256 d1;
        uint256 d0;
        {
            (uint256 x1, uint256 x0) = Math512Lib.fullMul(sumUpToThisRange1, a);
            if (sumUpToThisRange0 >= compensationAmount0) {
                // if `Xhat >= B` then compute `D = Yhat * A - y * (Xhat - B)`
                (d1, d0) = Math512Lib.fullMul(
                    rangeVirtualReserves1, sumUpToThisRange0 - compensationAmount0
                );
                (d1, d0) = Math512Lib.checkedSub(x1, x0, d1, d0);
            } else {
                // if `Xhat < B` then compute `D = Yhat * A + y * (B - Xhat)`
                (d1, d0) = Math512Lib.fullMul(
                    rangeVirtualReserves1, compensationAmount0 - sumUpToThisRange0
                );
                (d1, d0) = Math512Lib.checkedAdd(x1, x0, d1, d0);
            }
        }
        // Compute `sqrtDX96 := sqrt(D) * 2^96 <> sqrt(D * 2^192)`
        (d1, d0) = Math512Lib.checkedMul2Pow192(d1, d0);
        uint256 sqrtDX96 = Math512Lib.sqrt512(d1, d0);

        uint256 liquidityX96 = uint256(liquidity) << 96;
        // Reuse `d1, d0` to store numerator `L + sqrt(D)`.
        (d1, d0) = Math512Lib.checkedAdd(0, liquidityX96, 0, sqrtDX96);
        (uint256 upperBits, uint256 p1) = Math512Lib.div512by256(d1, d0, a);
        assert(upperBits == 0);

        return p1.toUint160();
    }
}
