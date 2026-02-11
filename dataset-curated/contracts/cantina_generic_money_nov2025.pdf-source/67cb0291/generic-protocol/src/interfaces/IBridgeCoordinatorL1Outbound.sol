// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IBridgeCoordinatorL1Outbound
 * @notice Interface for the L1 outbound bridge coordinator that manages cross-chain transfers
 * @dev Handles outbound bridging operations from Layer 1 to destination chains for GUSD transfers
 */
interface IBridgeCoordinatorL1Outbound {
    /**
     * @notice Bridges Generic units to another chain using the specified bridge protocol
     * @dev Restricts units on this chain and sends a message to release equivalent units on destination chain
     * @param bridgeType The identifier for the bridge protocol to use (must have registered adapter)
     * @param chainId The destination chain ID
     * @param onBehalf The address on this chain on whose behalf the units are bridged
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param sourceWhitelabel The whitelabeled unit token address on this chain, or zero address for native unit
     * token
     * @param destinationWhitelabel The whitelabeled unit token address on the destination chain (encoded as bytes32)
     * @param amount The amount of units to bridge
     * @param bridgeParams Protocol-specific parameters required by the bridge adapter
     * @return messageId Unique identifier for tracking the cross-chain message
     */
    function bridge(
        uint16 bridgeType,
        uint256 chainId,
        address onBehalf,
        bytes32 remoteRecipient,
        address sourceWhitelabel,
        bytes32 destinationWhitelabel,
        uint256 amount,
        bytes calldata bridgeParams
    )
        external
        payable
        returns (bytes32 messageId);

    /**
     * @notice Predeposits units for bridging to another chain
     * @dev Restricts units on this chain to be bridged later via bridgePredeposit
     * @param chainNickname The nickname of the destination chain
     * @param onBehalf The address on behalf of which the predeposit is made
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param amount The amount of units to predeposit
     */
    function predeposit(
        bytes32 chainNickname,
        address onBehalf,
        bytes32 remoteRecipient,
        uint256 amount
    )
        external;
}
