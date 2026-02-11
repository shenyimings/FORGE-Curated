// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FeeTypes} from "../types/FeeTypes.sol";
import {Reserves} from "../types/Reserves.sol";
import {MarginState} from "../types/MarginState.sol";
import {Math} from "./Math.sol";
import {FixedPoint96} from "./FixedPoint96.sol";
import {FeeLibrary} from "./FeeLibrary.sol";
import {PerLibrary} from "./PerLibrary.sol";
import {CustomRevert} from "./CustomRevert.sol";
import {ProtocolFeeLibrary} from "./ProtocolFeeLibrary.sol";

library InterestMath {
    using CustomRevert for bytes4;
    using FeeLibrary for uint24;
    using PerLibrary for uint256;

    function getBorrowRateByReserves(MarginState marginState, uint256 borrowReserve, uint256 mirrorReserve)
        internal
        pure
        returns (uint256 rate)
    {
        rate = marginState.rateBase();
        if (mirrorReserve == 0) {
            return rate;
        }
        uint256 useLevel = Math.mulDiv(mirrorReserve, PerLibrary.ONE_MILLION, borrowReserve);
        if (useLevel >= marginState.useHighLevel()) {
            rate += uint256(useLevel - marginState.useHighLevel()) * marginState.mHigh() / 100;
            useLevel = marginState.useHighLevel();
        }
        if (useLevel >= marginState.useMiddleLevel()) {
            rate += uint256(useLevel - marginState.useMiddleLevel()) * marginState.mMiddle() / 100;
            useLevel = marginState.useMiddleLevel();
        }
        return rate + useLevel * marginState.mLow() / 100;
    }

    function getBorrowRateCumulativeLast(
        uint256 timeElapsed,
        uint256 rate0CumulativeBefore,
        uint256 rate1CumulativeBefore,
        MarginState marginState,
        Reserves realReserves,
        Reserves mirrorReserve
    ) internal pure returns (uint256 rate0CumulativeLast, uint256 rate1CumulativeLast) {
        if (timeElapsed == 0) {
            return (rate0CumulativeBefore, rate1CumulativeBefore);
        }
        (uint256 realReserve0, uint256 realReserve1) = realReserves.reserves();
        (uint256 mirrorReserve0, uint256 mirrorReserve1) = mirrorReserve.reserves();
        uint256 rate0 = getBorrowRateByReserves(marginState, realReserve0 + mirrorReserve0, mirrorReserve0);
        uint256 rate0LastYear = PerLibrary.YEAR_TRILLION_SECONDS + rate0 * timeElapsed * PerLibrary.ONE_MILLION;
        rate0CumulativeLast = Math.mulDiv(rate0CumulativeBefore, rate0LastYear, PerLibrary.YEAR_TRILLION_SECONDS);
        uint256 rate1 = getBorrowRateByReserves(marginState, realReserve1 + mirrorReserve1, mirrorReserve1);
        uint256 rate1LastYear = PerLibrary.YEAR_TRILLION_SECONDS + rate1 * timeElapsed * PerLibrary.ONE_MILLION;
        rate1CumulativeLast = Math.mulDiv(rate1CumulativeBefore, rate1LastYear, PerLibrary.YEAR_TRILLION_SECONDS);
    }

    struct InterestUpdateParams {
        uint256 mirrorReserve;
        uint256 borrowCumulativeLast;
        uint256 borrowCumulativeBefore;
        uint256 interestReserve;
        uint256 pairReserve;
        uint256 lendReserve;
        uint256 depositCumulativeLast;
        uint24 protocolFee;
    }

    struct InterestUpdateResult {
        uint256 newMirrorReserve;
        uint256 newPairReserve;
        uint256 newLendReserve;
        uint256 newInterestReserve;
        uint256 newDepositCumulativeLast;
        uint256 pairInterest;
        bool changed;
    }

    function updateInterestForOne(InterestUpdateParams memory params)
        internal
        pure
        returns (InterestUpdateResult memory result)
    {
        result.newMirrorReserve = params.mirrorReserve;
        result.newPairReserve = params.pairReserve;
        result.newLendReserve = params.lendReserve;
        result.newInterestReserve = params.interestReserve;
        result.newDepositCumulativeLast = params.depositCumulativeLast;

        if (params.mirrorReserve > 0 && params.borrowCumulativeLast > params.borrowCumulativeBefore) {
            uint256 allInterest = Math.mulDiv(
                params.mirrorReserve * FixedPoint96.Q96, params.borrowCumulativeLast, params.borrowCumulativeBefore
            ) - params.mirrorReserve * FixedPoint96.Q96 + params.interestReserve;

            (uint256 protocolInterest,) =
                ProtocolFeeLibrary.splitFee(params.protocolFee, FeeTypes.INTERESTS, allInterest);

            if (protocolInterest == 0 || protocolInterest > FixedPoint96.Q96) {
                uint256 allInterestNoQ96 = allInterest / FixedPoint96.Q96;
                allInterestNoQ96 -= protocolInterest / FixedPoint96.Q96;

                result.pairInterest =
                    Math.mulDiv(allInterestNoQ96, params.pairReserve, params.pairReserve + params.lendReserve);

                if (allInterestNoQ96 > result.pairInterest) {
                    uint256 lendingInterest = allInterestNoQ96 - result.pairInterest;
                    result.newDepositCumulativeLast = Math.mulDiv(
                        params.depositCumulativeLast, params.lendReserve + lendingInterest, params.lendReserve
                    );
                    result.newLendReserve += lendingInterest;
                }

                result.newMirrorReserve += allInterestNoQ96;
                result.newPairReserve += result.pairInterest;
                result.changed = true;
                result.newInterestReserve = 0;
            } else {
                result.newInterestReserve = allInterest;
            }
        }
    }
}
