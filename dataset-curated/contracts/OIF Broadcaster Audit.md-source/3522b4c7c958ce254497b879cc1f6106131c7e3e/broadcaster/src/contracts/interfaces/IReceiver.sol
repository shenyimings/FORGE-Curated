// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBlockHashProver} from "./IBlockHashProver.sol";

/// @notice Reads messages from a broadcaster.
interface IReceiver {
    /// @notice Arguments required to read storage of an account on a remote chain.
    /// @dev    The storage proof is always for a single slot, if the proof is for multiple slots the IReceiver MUST revert
    /// @param  route The home chain addresses of the BlockHashProverPointers along the route to the remote chain.
    /// @param  bhpInputs The inputs to the BlockHashProver / BlockHashProverCopies.
    /// @param  storageProof Proof passed to the last BlockHashProver / BlockHashProverCopy
    ///                      to verify a storage slot given a target block hash.
    struct RemoteReadArgs {
        address[] route;
        bytes[] bhpInputs;
        bytes storageProof;
    }

    /// @notice Reads a broadcast message from a remote chain.
    /// @param  broadcasterReadArgs A RemoteReadArgs object:
    ///         - The route points to the broadcasting chain
    ///         - The account proof is for the broadcaster's account
    ///         - The storage proof is for the message slot
    /// @param  message The message to read.
    /// @param  publisher The address of the publisher who broadcast the message.
    /// @return broadcasterId The broadcaster's unique identifier.
    /// @return timestamp The timestamp when the message was broadcast.
    function verifyBroadcastMessage(RemoteReadArgs calldata broadcasterReadArgs, bytes32 message, address publisher)
        external
        view
        returns (bytes32 broadcasterId, uint256 timestamp);

    /// @notice Updates the block hash prover copy in storage.
    ///         Checks that BlockHashProverCopy has the same code hash as stored in the BlockHashProverPointer
    ///         Checks that the version is increasing.
    /// @param  bhpPointerReadArgs A RemoteReadArgs object:
    ///         - The route points to the BlockHashProverPointer's home chain
    ///         - The account proof is for the BlockHashProverPointer's account
    ///         - The storage proof is for the BLOCK_HASH_PROVER_POINTER_SLOT
    /// @param  bhpCopy The BlockHashProver copy on the local chain.
    /// @return bhpPointerId The ID of the BlockHashProverPointer
    function updateBlockHashProverCopy(RemoteReadArgs calldata bhpPointerReadArgs, IBlockHashProver bhpCopy)
        external
        returns (bytes32 bhpPointerId);

    /// @notice The BlockHashProverCopy on the local chain corresponding to the bhpPointerId
    ///         MUST return 0 if the BlockHashProverPointer does not exist.
    function blockHashProverCopy(bytes32 bhpPointerId) external view returns (IBlockHashProver bhpCopy);
}
