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

import {ImTokenOperationTypes} from "./ImToken.sol";

interface IPauser is ImTokenOperationTypes {
    enum PausableType {
        NonPausable,
        Host,
        Extension
    }

    struct PausableContract {
        address market;
        PausableType contractType;
    }

    error Pauser_EntryNotFound();
    error Pauser_NotAuthorized();
    error Pauser_AddressNotValid();
    error Pauser_AlreadyRegistered();
    error Pauser_ContractNotEnabled();

    event PauseAll();
    event MarketPaused(address indexed market);
    event MarketRemoved(address indexed market);
    event MarketAdded(address indexed market, PausableType marketType);
    event MarketPausedFor(address indexed market, OperationType pauseType);

    /**
     * @notice pauses all operations for a market
     * @param _market the mToken address
     */
    function emergencyPauseMarket(address _market) external;

    /**
     * @notice pauses a specific operation for a market
     * @param _market the mToken address
     * @param _pauseType the operation type
     */
    function emergencyPauseMarketFor(address _market, OperationType _pauseType) external;

    /**
     * @notice pauses all operations for all registered markets
     */
    function emergencyPauseAll() external;
}
