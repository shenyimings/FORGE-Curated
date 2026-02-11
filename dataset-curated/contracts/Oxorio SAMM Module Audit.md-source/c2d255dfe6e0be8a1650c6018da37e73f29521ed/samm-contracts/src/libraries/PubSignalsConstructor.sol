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
import "base64/base64.sol";

library PubSignalsConstructor {
    function getMsgHash(
        address to,
        uint256 value,
        bytes memory data,
        ISafe.Operation operation,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32 msgHash) {
        bytes32 calldataHash = keccak256(data);
        msgHash =
            keccak256(abi.encode(to, value, calldataHash, operation, nonce, deadline, address(this), block.chainid));
    }

    function getPubSignals(
        uint256 participantsRoot,
        string memory relayer,
        address to,
        uint256 value,
        bytes memory data,
        ISafe.Operation operation,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32[] memory pubSignals) {
        // public signals order: root, relayer, relayer_len, msg_hash, commit, pubkey_hash
        pubSignals = new bytes32[](172);

        // root
        pubSignals[0] = bytes32(participantsRoot);

        // relayer
        bytes memory relayerBytes = bytes(relayer);
        for (uint256 i = 0; i < relayerBytes.length; i++) {
            pubSignals[1 + i] = bytes32(uint256(uint8(relayerBytes[i])));
        }
        pubSignals[125] = bytes32(uint256(bytes(relayer).length));

        // msgHash
        bytes32 msgHash = getMsgHash(to, value, data, operation, nonce, deadline);
        bytes memory msgHash64 = bytes(Base64.encode(bytes.concat(msgHash)));
        for (uint256 i = 0; i < 44; i++) {
            pubSignals[126 + i] = bytes32(uint256(uint8(msgHash64[i])));
        }
    }
}
