// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMessageRecipient} from "@hyperlane-xyz/core/contracts/interfaces/IMessageRecipient.sol";
import {TypeCasts} from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import {MessageBridgeProver} from "./MessageBridgeProver.sol";
import {Semver} from "../libs/Semver.sol";
import {IMailbox, IPostDispatchHook} from "@hyperlane-xyz/core/contracts/interfaces/IMailbox.sol";

/**
 * @title HyperProver
 * @notice Prover implementation using Hyperlane's cross-chain messaging system
 * @dev Processes proof messages from Hyperlane mailbox and records proven intents
 */
contract HyperProver is IMessageRecipient, MessageBridgeProver, Semver {
    using TypeCasts for bytes32;

    /**
     * @notice Struct for unpacked data from _data parameter
     * @dev Only contains fields decoded from the _data parameter
     */
    struct UnpackedData {
        bytes32 sourceChainProver; // Address of prover on source chain
        bytes metadata; // Metadata for Hyperlane message
        address hookAddr; // Address of post-dispatch hook
    }

    /**
     * @notice Struct for Hyperlane dispatch parameters
     * @dev Consolidates message dispatch parameters to reduce stack usage
     */
    struct DispatchParams {
        uint32 destinationDomain; // Hyperlane domain ID
        bytes32 recipientAddress; // Recipient address encoded as bytes32
        bytes messageBody; // Encoded message body with intent hashes and claimants
        bytes metadata; // Additional metadata for the message
        IPostDispatchHook hook; // Post-dispatch hook contract
    }

    /**
     * @notice Constant indicating this contract uses Hyperlane for proving
     */
    string public constant PROOF_TYPE = "Hyperlane";

    /**
     * @notice Address of local Hyperlane mailbox
     */
    address public immutable MAILBOX;

    /**
     * @param mailbox Address of local Hyperlane mailbox
     * @param portal Address of Portal contract
     * @param provers Array of trusted prover addresses (as bytes32 for cross-VM compatibility)
     */
    constructor(
        address mailbox,
        address portal,
        bytes32[] memory provers
    ) MessageBridgeProver(portal, provers, 0) {
        if (mailbox == address(0)) revert MessengerContractCannotBeZeroAddress();
        MAILBOX = mailbox;
    }

    /**
     * @notice Handles incoming Hyperlane messages containing proof data
     * @dev Processes batch updates to proven intents from valid sources
     * @param origin Origin chain ID from the source chain
     * @param sender Address that dispatched the message on source chain
     * @param messageBody Encoded array of intent hashes and claimants
     */
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata messageBody
    ) public payable only(MAILBOX) {
        // Verify origin and sender are valid
        if (origin == 0) revert MessageOriginChainDomainIDCannotBeZero();

        // Validate sender is not zero
        if (sender == bytes32(0)) revert MessageSenderCannotBeZeroAddress();

        _handleCrossChainMessage(sender, messageBody);
    }

    /**
     * @notice Implementation of message dispatch for Hyperlane
     * @dev Called by base prove() function after common validations
     * @param domainID Domain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param data Additional data for message formatting
     * @param fee Fee amount for message dispatch
     */
    function _dispatchMessage(
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes calldata data,
        uint256 fee
    ) internal override {
        // Parse incoming data into a structured format for processing
        UnpackedData memory unpacked = _unpackData(data);

        // Prepare parameters for cross-chain message dispatch using a struct
        // to reduce stack usage and improve code maintainability
        DispatchParams memory params = _formatHyperlaneMessage(
            domainID,
            encodedProofs,
            unpacked
        );

        // Send the message through Hyperlane mailbox using params from the struct
        // Note: Some Hyperlane versions have different dispatch signatures.
        // This matches the expected signature for testing.
        IMailbox(MAILBOX).dispatch{value: fee}(
            params.destinationDomain,
            params.recipientAddress,
            params.messageBody,
            params.metadata,
            params.hook
        );
    }

    /**
     * @notice Calculates the fee required for Hyperlane message dispatch
     * @dev Queries the Mailbox contract for accurate fee estimation
     * @param domainID Domain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param data Additional data for message formatting
     * @return Fee amount required for message dispatch
     */
    function fetchFee(
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes calldata data
    ) public view override returns (uint256) {
        // Decode structured data from the raw input
        UnpackedData memory unpacked = _unpackData(data);

        // Process fee calculation using the decoded struct
        // This architecture separates decoding from core business logic
        return _fetchFee(domainID, encodedProofs, unpacked);
    }

    /**
     * @notice Decodes the raw cross-chain message data into a structured format
     * @dev Parses ABI-encoded parameters into the UnpackedData struct
     * @param data Raw message data containing source chain information
     * @return unpacked Structured representation of the decoded parameters
     */
    function _unpackData(
        bytes calldata data
    ) internal pure returns (UnpackedData memory unpacked) {
        unpacked = abi.decode(data, (UnpackedData));
    }

    /**
     * @notice Internal function to calculate the fee with pre-decoded data
     * @param domainID Domain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param unpacked Struct containing decoded data from data parameter
     * @return Fee amount required for message dispatch
     */
    function _fetchFee(
        uint64 domainID,
        bytes calldata encodedProofs,
        UnpackedData memory unpacked
    ) internal view returns (uint256) {
        // Format and prepare message parameters for dispatch
        DispatchParams memory params = _formatHyperlaneMessage(
            domainID,
            encodedProofs,
            unpacked
        );

        // Query Hyperlane mailbox for accurate fee estimate
        return
            IMailbox(MAILBOX).quoteDispatch(
                params.destinationDomain,
                params.recipientAddress,
                params.messageBody,
                params.metadata,
                params.hook
            );
    }

    /**
     * @notice Returns the proof type used by this prover
     * @return ProofType indicating Hyperlane proving mechanism
     */
    function getProofType() external pure override returns (string memory) {
        return PROOF_TYPE;
    }

    /**
     * @notice Formats data for Hyperlane message dispatch with encoded proofs
     * @dev Prepares all parameters needed for the Mailbox dispatch call
     * @param domainID Domain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param unpacked Struct containing decoded data from data parameter
     * @return params Structured dispatch parameters for Hyperlane message
     */
    function _formatHyperlaneMessage(
        uint64 domainID,
        bytes calldata encodedProofs,
        UnpackedData memory unpacked
    ) internal view returns (DispatchParams memory params) {
        // Convert domain ID to Hyperlane domain ID format with overflow check
        if (domainID > type(uint32).max) {
            revert DomainIdTooLarge(domainID);
        }
        params.destinationDomain = uint32(domainID);

        // Use the source chain prover address as the message recipient
        params.recipientAddress = unpacked.sourceChainProver;

        params.messageBody = encodedProofs;

        // Pass through metadata as provided
        params.metadata = unpacked.metadata;

        // Default to mailbox's hook if none provided, following Hyperlane best practices
        params.hook = (unpacked.hookAddr == address(0))
            ? IMailbox(MAILBOX).defaultHook()
            : IPostDispatchHook(unpacked.hookAddr);
    }
}
