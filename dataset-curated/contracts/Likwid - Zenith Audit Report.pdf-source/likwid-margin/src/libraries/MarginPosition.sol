// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.0;

import {Math} from "./Math.sol";
import {Reserves} from "../types/Reserves.sol";
import {CustomRevert} from "./CustomRevert.sol";
import {SwapMath} from "./SwapMath.sol";
import {PerLibrary} from "./PerLibrary.sol";
import {SafeCast} from "./SafeCast.sol";

/// @title MarginPosition
/// @notice Positions represent an owner address' margin positions
library MarginPosition {
    using CustomRevert for bytes4;
    using SafeCast for *;

    error CannotUpdateEmptyPosition();

    error InvalidBorrowAmount();

    error ChangeMarginAction();

    error NoChangeInPosition();

    error PositionLiquidated();

    struct State {
        bool marginForOne;
        uint128 marginAmount;
        uint128 marginTotal;
        uint256 depositCumulativeLast;
        uint128 debtAmount;
        uint256 borrowCumulativeLast;
    }

    function marginLevel(
        State memory self,
        Reserves pairReserves,
        uint256 borrowCumulativeLast,
        uint256 depositCumulativeLast
    ) internal pure returns (uint256 level) {
        if (self.debtAmount == 0 || !pairReserves.bothPositive()) {
            level = type(uint256).max;
        } else {
            uint256 marginAmount;
            uint256 marginTotal;
            uint256 positionValue;
            uint256 debtAmount;
            uint256 repayAmount;
            (uint128 reserve0, uint128 reserve1) = pairReserves.reserves();
            (uint256 reserveBorrow, uint256 reserveMargin) =
                self.marginForOne ? (reserve0, reserve1) : (reserve1, reserve0);
            if (self.depositCumulativeLast != 0) {
                marginAmount = Math.mulDiv(self.marginAmount, depositCumulativeLast, self.depositCumulativeLast);
                marginTotal = Math.mulDiv(self.marginTotal, depositCumulativeLast, self.depositCumulativeLast);
                positionValue = marginAmount + marginTotal;
            }
            if (self.borrowCumulativeLast != 0) {
                debtAmount = Math.mulDiv(self.debtAmount, borrowCumulativeLast, self.borrowCumulativeLast);
            }
            if (marginTotal > 0) {
                repayAmount = Math.mulDiv(reserveBorrow, positionValue, reserveMargin);
            } else {
                uint256 numerator = positionValue * reserveBorrow;
                uint256 denominator = reserveMargin + positionValue;
                repayAmount = numerator / denominator;
            }
            level = Math.mulDiv(repayAmount, PerLibrary.ONE_MILLION, debtAmount);
        }
    }

    function update(
        State storage self,
        uint256 borrowCumulativeLast,
        uint256 depositCumulativeLast,
        int128 marginChangeAmount,
        uint256 marginWithoutFee,
        uint256 borrowAmount,
        uint256 repayAmount
    ) internal returns (uint256 releaseAmount, uint256 realRepayAmount) {
        uint256 marginAmount;
        uint256 marginTotal;
        uint256 positionValue;
        uint256 debtAmount;
        if (self.depositCumulativeLast != 0) {
            marginAmount = Math.mulDiv(self.marginAmount, depositCumulativeLast, self.depositCumulativeLast);
            marginTotal = Math.mulDiv(self.marginTotal, depositCumulativeLast, self.depositCumulativeLast);
            positionValue = marginAmount + marginTotal;
        }
        if (self.borrowCumulativeLast != 0) {
            debtAmount = Math.mulDiv(self.debtAmount, borrowCumulativeLast, self.borrowCumulativeLast);
        }
        if (repayAmount > 0) {
            if (repayAmount > debtAmount) {
                realRepayAmount = debtAmount;
                releaseAmount = positionValue;
            } else {
                releaseAmount = Math.mulDiv(positionValue, repayAmount.toUint128(), debtAmount);
                realRepayAmount = repayAmount;
            }
            debtAmount -= uint128(realRepayAmount);
            if (marginTotal > 0) {
                uint256 marginAmountReleased = Math.mulDiv(releaseAmount, marginAmount, positionValue);
                marginAmount = marginAmount - marginAmountReleased;
                if (releaseAmount > marginAmountReleased) {
                    uint256 marginTotalReleased = releaseAmount - marginAmountReleased;
                    marginTotal = marginTotal - marginTotalReleased;
                }
            } else {
                marginAmount = marginAmount - releaseAmount;
            }
        } else {
            bool hasLeverage = marginTotal > 0 || marginWithoutFee > 0;
            if (marginChangeAmount > 0) {
                // modify
                marginAmount += uint128(marginChangeAmount);
                // margin or borrow
                if (borrowAmount > 0) {
                    if (hasLeverage && marginWithoutFee == 0) {
                        // when margin, marginWithoutFee should >0
                        ChangeMarginAction.selector.revertWith();
                    }
                    marginTotal += marginWithoutFee;
                    debtAmount += borrowAmount;
                }
            } else if (marginChangeAmount < 0) {
                //  repay or modify
                marginAmount -= uint128(-marginChangeAmount);
            }
        }

        self.marginAmount = marginAmount.toUint128();
        self.marginTotal = marginTotal.toUint128();
        self.depositCumulativeLast = depositCumulativeLast;
        self.debtAmount = debtAmount.toUint128();
        self.borrowCumulativeLast = borrowCumulativeLast;
    }

    function close(
        State storage self,
        Reserves pairReserves,
        uint24 lpFee,
        uint256 borrowCumulativeLast,
        uint256 depositCumulativeLast,
        uint256 rewardAmount,
        uint24 closeMillionth
    )
        internal
        returns (
            uint256 releaseAmount,
            uint256 repayAmount,
            uint256 closeAmount,
            uint256 lostAmount,
            uint256 swapFeeAmount
        )
    {
        if (closeMillionth == 0 || closeMillionth > PerLibrary.ONE_MILLION) {
            PerLibrary.InvalidMillionth.selector.revertWith();
        }
        if (self.debtAmount > 0) {
            uint256 marginAmount;
            uint256 marginTotal;
            uint256 positionValue;
            uint256 debtAmount;
            if (self.depositCumulativeLast != 0) {
                marginAmount = Math.mulDiv(self.marginAmount, depositCumulativeLast, self.depositCumulativeLast);
                marginTotal = Math.mulDiv(self.marginTotal, depositCumulativeLast, self.depositCumulativeLast);
                positionValue = marginAmount + marginTotal;
            }
            if (self.borrowCumulativeLast != 0) {
                debtAmount = Math.mulDiv(self.debtAmount, borrowCumulativeLast, self.borrowCumulativeLast);
            }
            positionValue -= rewardAmount;
            releaseAmount = Math.mulDiv(positionValue, closeMillionth, PerLibrary.ONE_MILLION);
            repayAmount = Math.mulDiv(debtAmount, closeMillionth, PerLibrary.ONE_MILLION);
            uint256 payedAmount;
            (payedAmount, swapFeeAmount) = SwapMath.getAmountOut(pairReserves, lpFee, !self.marginForOne, releaseAmount);
            if (releaseAmount < positionValue && repayAmount > payedAmount) {
                PositionLiquidated.selector.revertWith();
            } else {
                // releaseAmount == positionValue or repayAmount <= payedAmount
                (uint256 costAmount,) = SwapMath.getAmountIn(pairReserves, lpFee, !self.marginForOne, repayAmount);
                if (releaseAmount > costAmount) {
                    closeAmount = releaseAmount - costAmount;
                } else if (repayAmount > payedAmount) {
                    lostAmount = repayAmount - payedAmount;
                }
            }

            if (marginTotal > 0) {
                uint256 marginAmountReleased = Math.mulDiv(marginAmount, closeMillionth, PerLibrary.ONE_MILLION);
                marginAmount = marginAmount - marginAmountReleased;
                if (releaseAmount > marginAmountReleased) {
                    uint256 marginTotalReleased = releaseAmount - marginAmountReleased;
                    marginTotal = marginTotal - marginTotalReleased;
                }
            } else {
                marginAmount =
                    Math.mulDiv(marginAmount, PerLibrary.ONE_MILLION - closeMillionth, PerLibrary.ONE_MILLION);
            }
            debtAmount -= repayAmount;
            self.marginAmount = marginAmount.toUint128();
            self.marginTotal = marginTotal.toUint128();
            self.depositCumulativeLast = depositCumulativeLast;
            self.debtAmount = debtAmount.toUint128();
            self.borrowCumulativeLast = borrowCumulativeLast;
        }
    }
}
