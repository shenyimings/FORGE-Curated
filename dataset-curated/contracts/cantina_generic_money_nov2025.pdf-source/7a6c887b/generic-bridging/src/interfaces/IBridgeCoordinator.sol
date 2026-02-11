// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IBridgeCoordinator
 * @notice Interface for coordinating cross-chain bridge operations for unit tokens
 * @dev Manages routing between different bridge adapters and handles inbound/outbound bridging
 */
interface IBridgeCoordinator {
    /**
     * @notice Settles an inbound bridge operation by releasing (unlocking or minting) Generic units to the recipient
     * @dev Called by bridge adapters when receiving cross-chain messages to complete bridge-in operations
     * @param bridgeType The identifier for the bridge protocol that received the message
     * @param chainId The source chain ID where the bridge operation originated
     * @param remoteSender The original sender address on the source chain (encoded as bytes32)
     * @param message The encoded bridge message containing recipient and amount data
     * @param messageId Unique identifier for tracking the cross-chain message
     */
    function settleInboundMessage(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 remoteSender,
        bytes calldata message,
        bytes32 messageId
    )
        external;
}
