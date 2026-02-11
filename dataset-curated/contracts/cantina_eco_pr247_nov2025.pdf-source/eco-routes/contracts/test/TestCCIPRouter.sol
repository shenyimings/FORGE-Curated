// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title TestCCIPRouter
 * @notice Mock CCIP Router for testing purposes
 * @dev Simulates CCIP Router behavior for unit tests
 */
contract TestCCIPRouter {
    address public processor;
    uint256 public constant FEE = 100000;

    // Stored data from last ccipSend call
    uint64 public lastDestinationChainSelector;
    Client.EVM2AnyMessage public lastMessage;
    bytes32 public lastMessageId;

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        bytes data,
        uint256 fee
    );

    constructor(address _processor) {
        processor = _processor;
    }

    /**
     * @notice Simulates sending a CCIP message
     * @dev Stores message data and optionally delivers it to the processor
     * @param destinationChainSelector The destination chain selector
     * @param message The CCIP message to send
     * @return messageId A unique identifier for the message
     */
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable returns (bytes32 messageId) {
        require(msg.value >= FEE, "TestCCIPRouter: insufficient fee");

        // Store the message data
        lastDestinationChainSelector = destinationChainSelector;
        lastMessage = message;

        // Generate a unique message ID
        messageId = keccak256(
            abi.encodePacked(
                block.timestamp,
                destinationChainSelector,
                message.receiver,
                message.data
            )
        );
        lastMessageId = messageId;

        // Decode receiver address
        address receiverAddress = abi.decode(message.receiver, (address));

        emit MessageSent(
            messageId,
            destinationChainSelector,
            receiverAddress,
            message.data,
            msg.value
        );

        // If we have a processor, simulate the cross-chain delivery
        if (processor != address(0)) {
            // Create the Any2EVMMessage for the receiver
            Client.Any2EVMMessage memory receivedMessage = Client.Any2EVMMessage({
                messageId: messageId,
                sourceChainSelector: uint64(block.chainid),
                sender: message.receiver, // The sender on source chain becomes receiver on dest
                data: message.data,
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            });

            // Deliver to the processor
            IAny2EVMMessageReceiver(processor).ccipReceive(receivedMessage);
        }
    }

    /**
     * @notice Returns the fee for sending a message
     * @param destinationChainSelector The destination chain selector
     * @param message The message to estimate fee for
     * @return fee The fee amount in native token
     */
    function getFee(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage memory message
    ) external pure returns (uint256 fee) {
        // Simple fee calculation for testing
        // In production, this would be more complex
        return FEE;
    }

    /**
     * @notice Sets the processor address
     * @dev Allows updating which contract receives messages
     * @param _processor The new processor address
     */
    function setProcessor(address _processor) external {
        processor = _processor;
    }

    /**
     * @notice Manually trigger message delivery to processor
     * @dev Useful for testing receive functionality separately
     * @param sourceChainSelector The source chain selector
     * @param sender The sender address (as bytes)
     * @param data The message data
     */
    function deliverMessage(
        uint64 sourceChainSelector,
        bytes memory sender,
        bytes memory data
    ) external {
        require(processor != address(0), "TestCCIPRouter: no processor");

        bytes32 messageId = keccak256(
            abi.encodePacked(block.timestamp, sourceChainSelector, sender, data)
        );

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelector,
            sender: sender,
            data: data,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        IAny2EVMMessageReceiver(processor).ccipReceive(message);
    }
}
