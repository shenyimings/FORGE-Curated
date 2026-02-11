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

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {IGasFeesHelper} from "src/interfaces/IGasFeesHelper.sol";

library CommonLib {
    error CommonLib_LengthMismatch();
    error AmountNotValid();
    error ChainNotValid();
    error NotEnoughGasFee();

    function checkLengthMatch(uint256 l1, uint256 l2) internal pure {
        if (l1 != l2) revert CommonLib_LengthMismatch();
    }

    function checkLengthMatch(uint256 l1, uint256 l2, uint256 l3) internal pure {
        if (l1 != l2 || l2 != l3) revert CommonLib_LengthMismatch();
    }

    function computeSum(uint256[] calldata values) internal pure returns (uint256 sum) {
        uint256 length = values.length;
        for (uint256 i; i < length;) {
            sum += values[i];
            unchecked {
                ++i;
            }
        }
    }

    function checkHostToExtension(
        uint256 amount,
        uint32 dstChainId,
        uint256 msgValue,
        mapping(uint32 => bool) storage allowedChains,
        IGasFeesHelper gasHelper
    ) internal view {
        if (amount == 0) revert AmountNotValid();
        if (!allowedChains[dstChainId]) revert ChainNotValid();

        uint256 requiredGas = address(gasHelper) != address(0) ? gasHelper.gasFees(dstChainId) : 0;

        if (msgValue < requiredGas) revert NotEnoughGasFee();
    }
}
