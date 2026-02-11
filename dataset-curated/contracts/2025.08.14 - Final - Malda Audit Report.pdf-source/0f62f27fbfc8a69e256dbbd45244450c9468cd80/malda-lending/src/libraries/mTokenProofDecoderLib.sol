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

import {BytesLib} from "src/libraries/BytesLib.sol";

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

library mTokenProofDecoderLib {
    uint256 public constant ENTRY_SIZE = 113; // 112 + 1 for L1inclusion

    error mTokenProofDecoderLib_ChainNotFound();
    error mTokenProofDecoderLib_InvalidLength();
    error mTokenProofDecoderLib_InvalidInclusion();

    function decodeJournal(bytes memory journalData)
        internal
        pure
        returns (
            address sender,
            address market,
            uint256 accAmountIn,
            uint256 accAmountOut,
            uint32 chainId,
            uint32 dstChainId,
            bool L1inclusion
        )
    {
        require (journalData.length == ENTRY_SIZE, mTokenProofDecoderLib_InvalidLength());

        // decode action data
        // | Offset | Length | Data Type               |
        // |--------|---------|----------------------- |
        // | 0      | 20      | address sender         |
        // | 20     | 20      | address market         |
        // | 40     | 32      | uint256 accAmountIn    |
        // | 72     | 32      | uint256 accAmountOut   |
        // | 104    | 4       | uint32 chainId         |
        // | 108    | 4       | uint32 dstChainId      |
        // | 112    | 1       | bool L1inclusion       |
        sender = BytesLib.toAddress(BytesLib.slice(journalData, 0, 20), 0);
        market = BytesLib.toAddress(BytesLib.slice(journalData, 20, 20), 0);
        accAmountIn = BytesLib.toUint256(BytesLib.slice(journalData, 40, 32), 0);
        accAmountOut = BytesLib.toUint256(BytesLib.slice(journalData, 72, 32), 0);
        chainId = BytesLib.toUint32(BytesLib.slice(journalData, 104, 4), 0);
        dstChainId = BytesLib.toUint32(BytesLib.slice(journalData, 108, 4), 0);

        uint8 rawL1inclusion = BytesLib.toUint8(BytesLib.slice(journalData, 112, 1), 0);
        require(rawL1inclusion == 0 || rawL1inclusion == 1, mTokenProofDecoderLib_InvalidInclusion());
        L1inclusion = rawL1inclusion == 1;
    }

    function encodeJournal(
        address sender,
        address market,
        uint256 accAmountIn,
        uint256 accAmountOut,
        uint32 chainId,
        uint32 dstChainId,
        bool L1inclusion
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(sender, market, accAmountIn, accAmountOut, chainId, dstChainId, L1inclusion);
    }
}
