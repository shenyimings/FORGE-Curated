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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IRoles} from "./interfaces/IRoles.sol";

contract Roles is Ownable, IRoles {
    // ----------- STORAGE ------------

    mapping(address => mapping(bytes32 => bool)) private _roles;

    bytes32 public constant REBALANCER = keccak256("REBALANCER");
    bytes32 public constant PAUSE_MANAGER = keccak256("PAUSE_MANAGER");
    bytes32 public constant REBALANCER_EOA = keccak256("REBALANCER_EOA");
    bytes32 public constant GUARDIAN_PAUSE = keccak256("GUARDIAN_PAUSE");
    bytes32 public constant CHAINS_MANAGER = keccak256("CHAINS_MANAGER");
    bytes32 public constant PROOF_FORWARDER = keccak256("PROOF_FORWARDER");
    bytes32 public constant PROOF_BATCH_FORWARDER = keccak256("PROOF_BATCH_FORWARDER");
    bytes32 public constant SEQUENCER = keccak256("SEQUENCER");
    bytes32 public constant GUARDIAN_BRIDGE = keccak256("GUARDIAN_BRIDGE");
    bytes32 public constant GUARDIAN_ORACLE = keccak256("GUARDIAN_ORACLE");
    bytes32 public constant GUARDIAN_RESERVE = keccak256("GUARDIAN_RESERVE");
    bytes32 public constant GUARDIAN_BORROW_CAP = keccak256("GUARDIAN_BORROW_CAP");
    bytes32 public constant GUARDIAN_SUPPLY_CAP = keccak256("GUARDIAN_SUPPLY_CAP");
    bytes32 public constant GUARDIAN_BLACKLIST = keccak256("GUARDIAN_BLACKLIST");

    /**
     * @notice emitted when role is set
     */
    event Allowed(address indexed _contract, bytes32 indexed _role, bool _allowed);

    constructor(address _owner) Ownable(_owner) {}

    // ----------- VIEW ------------
    function isAllowedFor(address _contract, bytes32 _role) external view override returns (bool) {
        return _roles[_contract][_role];
    }

    // ----------- OWNER ------------
    /**
     * @notice Abiltity to allow a contract for a role or not
     * @param _contract the contract's address.
     * @param _role the bytes32 role.
     * @param _allowed the new status.
     */
    function allowFor(address _contract, bytes32 _role, bool _allowed) external onlyOwner {
        require(_contract != address(0) && _role != bytes32(0), Roles_InputNotValid());
        _roles[_contract][_role] = _allowed;
        emit Allowed(_contract, _role, _allowed);
    }
}
