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

interface IRoles {
    error Roles_InputNotValid();

    /**
     * @notice Returns REBALANCER role
     */
    function REBALANCER() external view returns (bytes32);

    /**
     * @notice Returns REBALANCER_EOA role
     */
    function REBALANCER_EOA() external view returns (bytes32);

    /**
     * @notice Returns GUARDIAN_PAUSE role
     */
    function GUARDIAN_PAUSE() external view returns (bytes32);

    /**
     * @notice Returns GUARDIAN_BRIDGE role
     */
    function GUARDIAN_BRIDGE() external view returns (bytes32);

    /**
     * @notice Returns GUARDIAN_BORROW_CAP role
     */
    function GUARDIAN_BORROW_CAP() external view returns (bytes32);

    /**
     * @notice Returns GUARDIAN_SUPPLY_CAP role
     */
    function GUARDIAN_SUPPLY_CAP() external view returns (bytes32);

    /**
     * @notice Returns GUARDIAN_RESERVE role
     */
    function GUARDIAN_RESERVE() external view returns (bytes32);

    /**
     * @notice Returns PROOF_FORWARDER role
     */
    function PROOF_FORWARDER() external view returns (bytes32);

    /**
     * @notice Returns PROOF_BATCH_FORWARDER role
     */
    function PROOF_BATCH_FORWARDER() external view returns (bytes32);

    /**
     * @notice Returns SEQUENCER role
     */
    function SEQUENCER() external view returns (bytes32);

    /**
     * @notice Returns PAUSE_MANAGER role
     */
    function PAUSE_MANAGER() external view returns (bytes32);

    /**
     * @notice Returns CHAINS_MANAGER role
     */
    function CHAINS_MANAGER() external view returns (bytes32);

    /**
     * @notice Returns GUARDIAN_ORACLE role
     */
    function GUARDIAN_ORACLE() external view returns (bytes32);
    
    /**
     * @notice Returns GUARDIAN_BLACKLIST role
     */
    function GUARDIAN_BLACKLIST() external view returns (bytes32);

    /**
     * @notice Returns allowance status for a contract and a role
     * @param _contract the contract address
     * @param _role the bytes32 role
     */
    function isAllowedFor(address _contract, bytes32 _role) external view returns (bool);
}
