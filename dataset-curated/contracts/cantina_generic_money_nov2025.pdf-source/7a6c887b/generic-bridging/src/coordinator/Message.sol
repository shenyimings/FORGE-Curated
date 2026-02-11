// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @notice Enum representing the type of cross-chain message
 */
enum MessageType {
    BRIDGE
}

/**
 * @notice Structure representing a cross-chain bridge message
 * @param messageType The type of the message (BRIDGE)
 * @param data The payload of the message
 */
struct Message {
    MessageType messageType;
    bytes data;
}

/**
 * @notice Structure representing the data for a bridge operation
 * @param sender The sender address on the source chain (as bytes32)
 * @param recipient The recipient address on the destination chain (as bytes32)
 * @param sourceWhitelabel The whitelabeled unit token address on the source chain (as bytes32)
 * @param destinationWhitelabel The whitelabeled unit token address on the destination chain (as bytes32)
 * @param amount The amount of tokens to bridge
 */
struct BridgeMessage {
    bytes32 sender;
    bytes32 recipient;
    bytes32 sourceWhitelabel;
    bytes32 destinationWhitelabel;
    uint256 amount;
}
