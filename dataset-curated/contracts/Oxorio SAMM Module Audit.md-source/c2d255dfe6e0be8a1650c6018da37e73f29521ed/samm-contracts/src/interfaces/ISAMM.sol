// SPDX-License-Identifier: GPL-3
/**
 *     Safe Anonymization Mail Module
 *     Copyright (C) 2024 OXORIO-FZCO
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
pragma solidity 0.8.23;

import {ISafe} from "../Safe/interfaces/ISafe.sol";
import {ISAMMEvents} from "./ISAMMEvents.sol";
import {ISAMMErrors} from "./ISAMMErrors.sol";
import {ISAMMGetters} from "./ISAMMGetters.sol";

interface ISAMM is ISAMMEvents, ISAMMErrors, ISAMMGetters {
    struct Proof {
        bytes proof;
        uint256 commit;
        string domain;
        bytes32 pubkeyHash;
        bool is2048sig;
    }

    struct TxAllowance {
        address to;
        bytes4 selector;
        uint256 amount;
    }

    function setup(
        address safe,
        uint256 participantsRoot,
        uint64 threshold,
        string calldata relayer,
        address dkimRegistry,
        TxAllowance[] calldata txAllowances
    ) external;

    function executeTransaction(
        address to,
        uint256 value,
        bytes memory data,
        ISafe.Operation operation,
        Proof[] calldata proofs,
        uint256 deadline
    ) external returns (bool success);

    function executeTransactionReturnData(
        address to,
        uint256 value,
        bytes memory data,
        ISafe.Operation operation,
        Proof[] calldata proofs,
        uint256 deadline
    ) external returns (bool success, bytes memory returnData);
}
