// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseBridgeCoordinator } from "./BaseBridgeCoordinator.sol";
import { BridgeMessage, Message, MessageType } from "./Message.sol";

abstract contract BridgeMessageCoordinator is BaseBridgeCoordinator {
    /**
     * @notice Emitted when units are bridged out to another chain
     * @param sender The address that initiated the bridge operation
     * @param owner The address on this chain on whose behalf the units are bridged
     * @param remoteRecipient The recipient address on the destination chain (as bytes32)
     * @param amount The amount of units being bridged
     * @param messageId Unique identifier for tracking the bridge message
     * @param messageData The encoded bridge message
     */
    event BridgedOut(
        address sender,
        address indexed owner,
        bytes32 indexed remoteRecipient,
        uint256 amount,
        bytes32 indexed messageId,
        BridgeMessage messageData
    );
    /**
     * @notice Emitted when units are bridged in from another chain
     * @param remoteSender The sender address on the source chain (as bytes32)
     * @param recipient The recipient address on this chain that received the units
     * @param amount The amount of units being bridged
     * @param messageId Unique identifier for tracking the bridge message
     * @param messageData The encoded bridge message
     */
    event BridgedIn(
        bytes32 indexed remoteSender,
        address indexed recipient,
        uint256 amount,
        bytes32 indexed messageId,
        BridgeMessage messageData
    );
    /**
     * @notice Emitted when a rollback bridge operation is initiated
     * @param rollbackedMessageId The original message ID that is being rollbacked
     * @param messageId The unique identifier for tracking the rollback message
     */
    event BridgeRollbackedOut(bytes32 indexed rollbackedMessageId, bytes32 indexed messageId);

    /**
     * @notice Thrown when the decoded on-behalf address is zero
     */
    error BridgeMessage_InvalidOnBehalf();
    /**
     * @notice Thrown when the decoded recipient address is zero
     */
    error BridgeMessage_InvalidRecipient();
    /**
     * @notice Thrown when the remote recipient parameter is zero
     */
    error BridgeMessage_InvalidRemoteRecipient();
    /**
     * @notice Thrown when the bridge amount is zero
     */
    error BridgeMessage_InvalidAmount();
    /**
     * @notice Thrown when there is no recorded failed message execution for a given message ID
     */
    error BridgeMessage_NoFailedMessageExecution();
    /**
     * @notice Thrown when the rollback message data does not match a failed message
     */
    error BridgeMessage_InvalidFailedMessageData();
    /**
     * @notice Thrown when the original message is not of type BRIDGE
     */
    error BridgeMessage_InvalidMessageType();
    /**
     * @notice Thrown when there is no sender address to rollback to
     */
    error BridgeMessage_NoSenderToRollback();

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
        nonReentrant
        returns (bytes32 messageId)
    {
        require(onBehalf != address(0), BridgeMessage_InvalidOnBehalf());
        require(remoteRecipient != bytes32(0), BridgeMessage_InvalidRemoteRecipient());
        require(amount > 0, BridgeMessage_InvalidAmount());

        BridgeMessage memory bridgeMessage = BridgeMessage({
            sender: encodeOmnichainAddress(onBehalf),
            recipient: remoteRecipient,
            sourceWhitelabel: encodeOmnichainAddress(sourceWhitelabel),
            destinationWhitelabel: destinationWhitelabel,
            amount: amount
        });
        messageId = _dispatchMessage(bridgeType, chainId, encodeBridgeMessage(bridgeMessage), bridgeParams);

        _restrictUnits(sourceWhitelabel, msg.sender, amount);

        emit BridgedOut(msg.sender, onBehalf, remoteRecipient, amount, messageId, bridgeMessage);
    }

    /**
     * @notice Initiates a rollback of a failed inbound bridge operation
     * @dev Validates the failed message and sends a rollback message to the source chain
     * @param bridgeType The identifier for the bridge protocol to use (must have registered adapter)
     * @param originalChainId The chain id of the failed message
     * @param originalMessageData The original bridge message data that failed execution
     * @param originalMessageId Unique identifier of the original cross-chain message
     * @param bridgeParams Protocol-specific parameters required by the bridge adapter
     * @return rollbackMessageId Unique identifier for tracking the rollback cross-chain message
     */
    function rollback(
        uint16 bridgeType,
        uint256 originalChainId,
        bytes calldata originalMessageData,
        bytes32 originalMessageId,
        bytes calldata bridgeParams
    )
        external
        payable
        nonReentrant
        returns (bytes32 rollbackMessageId)
    {
        bytes32 failedMessageExecution = failedMessageExecutions[originalMessageId];
        require(failedMessageExecution != bytes32(0), BridgeMessage_NoFailedMessageExecution());
        require(
            failedMessageExecution == _failedMessageHash(originalChainId, originalMessageData),
            BridgeMessage_InvalidFailedMessageData()
        );
        delete failedMessageExecutions[originalMessageId];

        Message memory originalMessage = abi.decode(originalMessageData, (Message));
        require(originalMessage.messageType == MessageType.BRIDGE, BridgeMessage_InvalidMessageType());
        BridgeMessage memory bridgeMessage = abi.decode(originalMessage.data, (BridgeMessage));
        require(bridgeMessage.sender != bytes32(0), BridgeMessage_NoSenderToRollback());

        BridgeMessage memory rollbackMessage = BridgeMessage({
            sender: bytes32(0),
            recipient: bridgeMessage.sender,
            sourceWhitelabel: bridgeMessage.destinationWhitelabel,
            destinationWhitelabel: bridgeMessage.sourceWhitelabel,
            amount: bridgeMessage.amount
        });
        rollbackMessageId =
            _dispatchMessage(bridgeType, originalChainId, encodeBridgeMessage(rollbackMessage), bridgeParams);

        emit BridgedOut(
            msg.sender,
            address(0),
            rollbackMessage.recipient,
            rollbackMessage.amount,
            rollbackMessageId,
            rollbackMessage
        );
        emit BridgeRollbackedOut(originalMessageId, rollbackMessageId);
    }

    /**
     * @notice Settles an inbound bridge message
     * @dev Decodes the bridge message and releases units to the recipient on this chain
     * @param messageData The encoded bridge message containing recipient and amount data
     * @param messageId Unique identifier for tracking the cross-chain message
     */
    function _settleInboundBridgeMessage(bytes memory messageData, bytes32 messageId) internal {
        BridgeMessage memory message = abi.decode(messageData, (BridgeMessage));
        address recipient = decodeOmnichainAddress(message.recipient);
        uint256 amount = message.amount;

        require(recipient != address(0), BridgeMessage_InvalidRecipient());
        require(amount > 0, BridgeMessage_InvalidAmount());
        _releaseUnits(decodeOmnichainAddress(message.destinationWhitelabel), recipient, amount);
        emit BridgedIn(message.sender, recipient, amount, messageId, message);
    }

    /**
     * @notice Encodes a BRIDGE type message for cross-chain transmission
     * @param message The BridgeMessage struct containing bridge details
     * @return The ABI-encoded message ready for dispatch
     */
    function encodeBridgeMessage(BridgeMessage memory message) public pure returns (bytes memory) {
        return abi.encode(Message({ messageType: MessageType.BRIDGE, data: abi.encode(message) }));
    }
}
