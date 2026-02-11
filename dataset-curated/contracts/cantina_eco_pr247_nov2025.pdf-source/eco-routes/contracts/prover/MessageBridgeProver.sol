/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseProver} from "./BaseProver.sol";
import {IMessageBridgeProver} from "../interfaces/IMessageBridgeProver.sol";
import {Whitelist} from "../libs/Whitelist.sol";

/**
 * @title MessageBridgeProver
 * @notice Abstract contract for cross-chain message-based proving mechanisms
 * @dev Extends BaseProver with functionality for message bridge provers like Hyperlane and Metalayer
 */
abstract contract MessageBridgeProver is
    BaseProver,
    IMessageBridgeProver,
    Whitelist
{
    /**
     * @notice Minimum gas limit for cross-chain message dispatch
     * @dev Set at deployment and cannot be changed afterward. Gas limits below this value will be increased to this minimum.
     */
    uint256 public immutable MIN_GAS_LIMIT;

    /**
     * @notice Default minimum gas limit for cross-chain messages
     * @dev Used if no specific value is provided during contract deployment
     */
    uint256 private constant DEFAULT_MIN_GAS_LIMIT = 200_000;

    /**
     * @notice Initializes the MessageBridgeProver contract
     * @param portal Address of the Portal contract
     * @param provers Array of trusted prover addresses (as bytes32 for cross-VM compatibility)
     * @param minGasLimit Minimum gas limit for cross-chain messages (200k if not specified or zero)
     */
    constructor(
        address portal,
        bytes32[] memory provers,
        uint256 minGasLimit
    ) BaseProver(portal) Whitelist(provers) {
        MIN_GAS_LIMIT = minGasLimit > 0 ? minGasLimit : 200_000;
    }

    /**
     * @notice Modifier to restrict function access to a specific sender
     * @param expectedSender Address that is expected to be the sender
     */
    modifier only(address expectedSender) {
        if (msg.sender != expectedSender) {
            revert UnauthorizedSender(expectedSender, msg.sender);
        }

        _;
    }

    /**
     * @notice Send refund to the user if they've overpaid
     * @param recipient Address to send the refund to
     * @param amount Amount to refund
     */
    function _sendRefund(address recipient, uint256 amount) internal {
        if (recipient == address(0) || amount == 0) {
            return;
        }

        payable(recipient).transfer(amount);
    }

    /**
     * @notice Handles cross-chain messages containing proof data
     * @dev Common implementation to validate and process cross-chain messages
     * @param messageSender Address that dispatched the message on source chain (as bytes32 for cross-VM compatibility)
     * @param message Encoded message with chain ID prepended, followed by (intentHash, claimant) pairs
     */
    function _handleCrossChainMessage(
        bytes32 messageSender,
        bytes calldata message
    ) internal {
        // Verify dispatch originated from a whitelisted prover address
        if (!isWhitelisted(messageSender)) {
            revert UnauthorizedIncomingProof(messageSender);
        }

        // Extract the chain ID from the beginning of the message
        // Message format: [chainId (8 bytes as uint64)] + [encodedProofs]
        if (message.length < 8) {
            revert InvalidProofMessage();
        }

        // Convert raw 8 bytes to uint64 - the chain ID is stored as big-endian bytes
        bytes8 chainIdBytes = bytes8(message[0:8]);
        uint64 actualChainId = uint64(chainIdBytes);
        bytes calldata encodedProofs = message[8:];

        // Process the intent proofs using the chain ID extracted from the message
        _processIntentProofs(encodedProofs, actualChainId);
    }

    /**
     * @notice Common prove function implementation for message bridge provers
     * @dev Handles fee calculation, validation, and message dispatch
     * @param sender Address that initiated the proving request
     * @param domainID Bridge-specific domain ID of the source chain (where the intent was created).
     *        IMPORTANT: This is NOT the chain ID. Each bridge provider uses their own
     *        domain ID mapping system. You MUST check with the specific bridge provider
     *        (Hyperlane, LayerZero, Metalayer) documentation to determine the correct
     *        domain ID for the source chain.
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param data Additional data for message formatting
     */
    function prove(
        address sender,
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes calldata data
    ) external payable virtual override only(PORTAL) {
        // Calculate fee using implementation-specific logic
        uint256 fee = fetchFee(domainID, encodedProofs, data);

        // Check if enough fee was provided
        if (msg.value < fee) {
            revert InsufficientFee(fee);
        }

        // Calculate refund amount if overpaid
        uint256 refundAmount = msg.value > fee ? msg.value - fee : 0;

        // Dispatch message using implementation-specific logic
        _dispatchMessage(domainID, encodedProofs, data, fee);

        // Send refund if needed
        _sendRefund(sender, refundAmount);
    }

    /**
     * @notice Abstract function to dispatch message via specific bridge
     * @dev Must be implemented by concrete provers (HyperProver, MetaProver)
     * @param sourceChainId Chain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param data Additional data for message formatting
     * @param fee Fee amount for message dispatch
     */
    function _dispatchMessage(
        uint64 sourceChainId,
        bytes calldata encodedProofs,
        bytes calldata data,
        uint256 fee
    ) internal virtual;

    /**
     * @notice Fetches fee required for message dispatch
     * @dev Must be implemented by concrete provers to calculate bridge-specific fees
     * @param sourceChainId Chain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param data Additional data for message formatting
     * @return Fee amount required for message dispatch
     */
    function fetchFee(
        uint64 sourceChainId,
        bytes calldata encodedProofs,
        bytes calldata data
    ) public view virtual returns (uint256);
}
