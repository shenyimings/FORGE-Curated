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

// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {IRoles} from "src/interfaces/IRoles.sol";

abstract contract BaseBridge {
    // ----------- STORAGE ------------
    IRoles public roles;

    error BaseBridge_NotAuthorized();
    error BaseBridge_AmountMismatch();
    error BaseBridge_AmountNotValid();
    error BaseBridge_AddressNotValid();

    constructor(address _roles) {
        require(_roles != address(0), BaseBridge_AddressNotValid());

        roles = IRoles(_roles);
    }

    modifier onlyBridgeConfigurator() {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_BRIDGE())) revert BaseBridge_NotAuthorized();
        _;
    }

    modifier onlyRebalancer() {
        if (!roles.isAllowedFor(msg.sender, roles.REBALANCER())) revert BaseBridge_NotAuthorized();
        _;
    }
}
