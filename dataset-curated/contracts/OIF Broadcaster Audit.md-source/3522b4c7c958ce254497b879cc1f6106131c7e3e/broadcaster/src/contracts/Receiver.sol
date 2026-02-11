// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IReceiver} from "./interfaces/IReceiver.sol";
import {IBlockHashProver} from "./interfaces/IBlockHashProver.sol";
import {IBlockHashProverPointer} from "./interfaces/IBlockHashProverPointer.sol";
import {BLOCK_HASH_PROVER_POINTER_SLOT} from "./BlockHashProverPointer.sol";

contract Receiver is IReceiver {
    mapping(bytes32 blockHashProverPointerId => IBlockHashProver blockHashProverCopy) private _blockHashProverCopies;

    error InvalidRouteLength();
    error EmptyRoute();
    error ProverCopyNotFound();
    error MessageNotFound();
    error WrongMessageSlot();
    error WrongBlockHashProverPointerSlot();
    error DifferentCodeHash();
    error NewerProverVersion();

    function verifyBroadcastMessage(RemoteReadArgs calldata broadcasterReadArgs, bytes32 message, address publisher)
        external
        view
        returns (bytes32 broadcasterId, uint256 timestamp)
    {
        uint256 messageSlot;
        bytes32 slotValue;

        (broadcasterId, messageSlot, slotValue) = _readRemoteSlot(broadcasterReadArgs);

        if (slotValue == 0) {
            revert MessageNotFound();
        }

        uint256 expectedMessageSlot = uint256(keccak256(abi.encode(message, publisher)));
        if (messageSlot != expectedMessageSlot) {
            revert WrongMessageSlot();
        }

        timestamp = uint256(slotValue);
    }

    function updateBlockHashProverCopy(RemoteReadArgs calldata bhpPointerReadArgs, IBlockHashProver bhpCopy)
        external
        returns (bytes32 bhpPointerId)
    {
        uint256 slot;
        bytes32 bhpCodeHash;
        (bhpPointerId, slot, bhpCodeHash) = _readRemoteSlot(bhpPointerReadArgs);

        if (slot != uint256(BLOCK_HASH_PROVER_POINTER_SLOT)) {
            revert WrongBlockHashProverPointerSlot();
        }

        if (address(bhpCopy).codehash != bhpCodeHash) {
            revert DifferentCodeHash();
        }

        IBlockHashProver oldProverCopy = _blockHashProverCopies[bhpPointerId];

        if (oldProverCopy.version() >= bhpCopy.version()) {
            revert NewerProverVersion();
        }

        _blockHashProverCopies[bhpPointerId] = bhpCopy;
    }

    /// @notice The BlockHashProverCopy on the local chain corresponding to the bhpPointerId
    ///         MUST return 0 if the BlockHashProverPointer does not exist.
    function blockHashProverCopy(bytes32 bhpPointerId) external view returns (IBlockHashProver bhpCopy) {
        bhpCopy = _blockHashProverCopies[bhpPointerId];
    }

    function _readRemoteSlot(RemoteReadArgs calldata readArgs)
        internal
        view
        returns (bytes32 remoteAccountId, uint256 slot, bytes32 slotValue)
    {
        if (readArgs.route.length != readArgs.bhpInputs.length) {
            revert InvalidRouteLength();
        }

        if (readArgs.route.length == 0) {
            revert EmptyRoute();
        }

        IBlockHashProver prover;
        bytes32 blockHash;

        for (uint256 i = 0; i < readArgs.route.length; i++) {
            remoteAccountId = accumulator(remoteAccountId, readArgs.route[i]);

            if (i == 0) {
                prover = IBlockHashProver(IBlockHashProverPointer(readArgs.route[0]).implementationAddress());
                blockHash = prover.getTargetBlockHash(readArgs.bhpInputs[0]);
            } else {
                prover = _blockHashProverCopies[remoteAccountId];
                if (address(prover) == address(0)) {
                    revert ProverCopyNotFound();
                }

                blockHash = prover.verifyTargetBlockHash(blockHash, readArgs.bhpInputs[i]);
            }
        }

        address remoteAccount;

        (remoteAccount, slot, slotValue) = prover.verifyStorageSlot(blockHash, readArgs.storageProof);

        remoteAccountId = accumulator(remoteAccountId, remoteAccount);
    }

    function accumulator(bytes32 acc, address addr) internal pure returns (bytes32) {
        return keccak256(abi.encode(acc, addr));
    }
}
