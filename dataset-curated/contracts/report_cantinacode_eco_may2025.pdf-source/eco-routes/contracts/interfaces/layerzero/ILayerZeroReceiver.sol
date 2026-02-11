// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ILayerZeroReceiver
 * @notice Interface for contracts that receive LayerZero messages
 * @dev Must be implemented by contracts that want to receive cross-chain messages
 */
interface ILayerZeroReceiver {
    /**
     * @notice Struct containing origin information for received messages
     * @param srcEid Source endpoint ID
     * @param sender Sender address on source chain (as bytes32)
     * @param nonce Message nonce
     */
    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    /**
     * @notice Handle incoming LayerZero message
     * @dev Called by LayerZero endpoint when receiving a message
     * @param origin Origin information containing source chain and sender
     * @param guid Globally unique identifier for the message
     * @param message The message payload
     * @param executor Address of the executor (for optional execution)
     * @param extraData Additional data passed by the executor
     */
    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable;

    /**
     * @notice Check if path is allowed for receiving messages
     * @param origin Origin information to check
     * @return Whether the origin is allowed
     */
    function allowInitializePath(
        Origin calldata origin
    ) external view returns (bool);

    /**
     * @notice Get next expected nonce from a source
     * @param srcEid Source endpoint ID
     * @param sender Sender address on source chain
     * @return Next expected nonce
     */
    function nextNonce(
        uint32 srcEid,
        bytes32 sender
    ) external view returns (uint64);
}
