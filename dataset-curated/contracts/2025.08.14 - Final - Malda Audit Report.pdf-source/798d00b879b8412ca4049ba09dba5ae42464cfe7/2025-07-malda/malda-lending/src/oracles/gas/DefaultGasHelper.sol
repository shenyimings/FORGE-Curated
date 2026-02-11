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

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DefaultGasHelper is Ownable {
    // ----------- STORAGE ------------
    mapping(uint32 => uint256) public gasFees;

    // ----------- EVENTS ------------
    event GasFeeUpdated(uint32 indexed dstChainid, uint256 amount);

    constructor(address _owner) Ownable(_owner) {}

    // ----------- OWNER ------------
    /**
     * @notice Sets the gas fee
     * @param dstChainId the destination chain id
     * @param amount the gas fee amount
     */
    function setGasFee(uint32 dstChainId, uint256 amount) external onlyOwner {
        gasFees[dstChainId] = amount;
        emit GasFeeUpdated(dstChainId, amount);
    }
}
