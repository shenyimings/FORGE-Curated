// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {ImToken, ImTokenOperationTypes} from "src/interfaces/ImToken.sol";
import {IOperator} from "src/interfaces/IOperator.sol";

contract LiquidationHelper {
    function getBorrowerPosition(address borrower, address market)
        external
        view
        returns (bool shouldLiquidate, uint256 repayAmount)
    {
        shouldLiquidate = false;
        repayAmount = 0;

        // check if market is paused for liquidation
        IOperator operator = IOperator(ImToken(market).operator());
        if (operator.isPaused(market, ImTokenOperationTypes.OperationType.Liquidate)) {
            return (shouldLiquidate, repayAmount);
        }

        /**
         * // check if market is listed
         *     (bool isListed) = operator.isMarketListed(market);
         *     if (!isListed) {
         *         return (shouldLiquidate, repayAmount);
         *     }
         */

        // get borrow balance
        ImToken marketContract = ImToken(market);
        uint256 borrowBalance = marketContract.borrowBalanceStored(borrower);
        if (borrowBalance == 0) {
            return (shouldLiquidate, repayAmount);
        }

        // check shortfall
        (, uint256 shortfall) = operator.getHypotheticalAccountLiquidity(borrower, address(0), 0, 0);
        if (shortfall == 0) {
            return (shouldLiquidate, repayAmount);
        }

        // calculate maxClose
        uint256 closeFactorMantissa = operator.closeFactorMantissa();
        repayAmount = (borrowBalance * closeFactorMantissa) / 1e18;
        shouldLiquidate = true;
    }
}
