// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMetalayerRecipient, ReadOperation} from "@metalayer/contracts/src/interfaces/IMetalayerRecipient.sol";
import {FinalityState} from "@metalayer/contracts/src/lib/MetalayerMessage.sol";
import {TypeCasts} from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import {MessageBridgeProver} from "./MessageBridgeProver.sol";
// Import Semver for versioning support
import {Semver} from "../libs/Semver.sol";
import {StandardHookMetadata} from "@hyperlane-xyz/core/contracts/hooks/libs/StandardHookMetadata.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IMetalayerRouterExt} from "../interfaces/IMetalayerRouterExt.sol";

/**
 * @title MetaProver
 * @notice Prover implementation using Caldera Metalayer's cross-chain messaging system
 * @notice the terms "source" and "destination" are used in reference to a given intent: created on source chain, fulfilled on destination chain
 * @dev Processes proof messages from Metalayer router and records proven intents
 */
contract MetaProver is IMetalayerRecipient, MessageBridgeProver, Semver {
    using TypeCasts for bytes32;
    using TypeCasts for address;
    using SafeCast for uint256;

    /**
     * @notice Struct for unpacked data from _data parameter
     * @dev Contains fields decoded from the _data parameter
     */
    struct UnpackedData {
        bytes32 sourceChainProver; // Address of prover on source chain
        uint256 gasLimit; // Gas limit for execution
    }

    /**
     * @notice Constant indicating this contract uses Metalayer for proving
     */
    string public constant PROOF_TYPE = "Meta";

    /**
     * @notice ETH message value used in fee calculation metadata
     * @dev Set to very high value (1e36) to avoid fee calculation failures
     *      in the Metalayer router's quote dispatch function
     */
    uint256 private immutable ETH_QUOTE_VALUE = 1e36;

    /**
     * @notice Address of local Metalayer router
     */
    IMetalayerRouterExt public immutable ROUTER;

    /**
     * @notice Initializes the MetaProver contract
     * @param router Address of local Metalayer router
     * @param portal Address of Portal contract
     * @param provers Array of trusted prover addresses (as bytes32 for cross-VM compatibility)
     * @param minGasLimit Minimum gas limit for cross-chain messages (200k if zero)
     */
    constructor(
        address router,
        address portal,
        bytes32[] memory provers,
        uint256 minGasLimit
    ) MessageBridgeProver(portal, provers, minGasLimit) {
        if (router == address(0)) revert MessengerContractCannotBeZeroAddress();

        ROUTER = IMetalayerRouterExt(router);
    }

    /**
     * @notice Handles incoming Metalayer messages containing proof data
     * @dev Processes batch updates to proven intents from valid sources
     * @dev called by the Metalayer Router on the source chain
     * @param origin Origin chain ID from the destination chain
     * @param sender Address that dispatched the message on destination chain
     * @param message Encoded array of intent hashes and claimants
     */
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata message,
        ReadOperation[] calldata /* operations */,
        bytes[] calldata /* operationsData */
    ) external payable only(address(ROUTER)) {
        // Verify origin and sender are valid
        if (origin == 0) revert MessageOriginChainDomainIDCannotBeZero();

        // Validate sender is not zero
        if (sender == bytes32(0)) revert MessageSenderCannotBeZeroAddress();

        _handleCrossChainMessage(sender, message);
    }

    /**
     * @notice Decodes the raw cross-chain message data into a structured format
     * @dev Parses ABI-encoded parameters into the UnpackedData struct and enforces minimum gas limit
     * @param data Raw message data containing source chain information
     * @return unpacked Structured representation of the decoded parameters with validated gas limit
     */
    function _unpackData(
        bytes calldata data
    ) internal view returns (UnpackedData memory unpacked) {
        unpacked = abi.decode(data, (UnpackedData));

        // Enforce minimum gas limit to prevent underfunded transactions
        if (unpacked.gasLimit < MIN_GAS_LIMIT) {
            unpacked.gasLimit = MIN_GAS_LIMIT;
        }
    }

    /**
     * @notice Implementation of message dispatch for Metalayer
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
        // Parse incoming data into a structured format
        UnpackedData memory unpacked = _unpackData(data);

        // Format message for dispatch using pre-decoded value
        (
            uint32 sourceChainDomain,
            bytes32 recipient,
            bytes memory message
        ) = _formatMetalayerMessage(
                domainID,
                encodedProofs,
                unpacked.sourceChainProver
            );

        // Call Metalayer router's send message function
        ROUTER.dispatch{value: fee}(
            sourceChainDomain,
            recipient,
            new ReadOperation[](0),
            message,
            FinalityState.INSTANT,
            unpacked.gasLimit
        );
    }

    /**
     * @notice Fetches fee required for message dispatch
     * @dev Uses custom hook metadata with actual gas limit to ensure accurate fee estimation.
     *      Fixes issue where 3-parameter quoteDispatch used hardcoded 100k gas limit.
     * @param domainID Domain ID of source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param data Additional data containing gas limit that will be used in dispatch
     * @return Fee amount required for message dispatch
     */
    function fetchFee(
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes calldata data
    ) public view override returns (uint256) {
        // Delegate to internal function with pre-decoded value
        return _fetchFee(domainID, encodedProofs, _unpackData(data));
    }

    /**
     * @notice Internal function to calculate fee with pre-decoded data
     * @dev Uses actual gas limit from unpacked data to ensure accurate fee estimation
     * @param domainID Domain ID of source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param unpacked Pre-decoded data including actual gas limit that will be used
     * @return Fee amount required for message dispatch
     */
    function _fetchFee(
        uint64 domainID,
        bytes calldata encodedProofs,
        UnpackedData memory unpacked
    ) internal view returns (uint256) {
        (
            uint32 sourceChainDomain,
            bytes32 recipient,
            bytes memory message
        ) = _formatMetalayerMessage(
                domainID,
                encodedProofs,
                unpacked.sourceChainProver
            );

        // Create custom hook metadata with the actual gas limit that will be used in dispatch
        bytes memory feeHookMetadata = StandardHookMetadata.formatMetadata(
            ETH_QUOTE_VALUE,
            unpacked.gasLimit, // Use actual gas limit (min 200k)
            msg.sender, // Refund address
            bytes("") // Optional custom metadata
        );

        return
            ROUTER.quoteDispatch(
                sourceChainDomain,
                recipient,
                message,
                feeHookMetadata
            );
    }

    /**
     * @notice Returns the proof type used by this prover
     * @return ProofType indicating Metalayer proving mechanism
     */
    function getProofType() external pure override returns (string memory) {
        return PROOF_TYPE;
    }

    /**
     * @notice Formats data for Metalayer message dispatch with encoded proofs
     * @param domainID Domain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param sourceChainProver Pre-decoded prover address on source chain
     * @return domain Metalayer domain ID
     * @return recipient Recipient address encoded as bytes32
     * @return message Encoded message body with intent hashes and claimants
     */
    function _formatMetalayerMessage(
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes32 sourceChainProver
    )
        internal
        pure
        returns (uint32 domain, bytes32 recipient, bytes memory message)
    {
        // Convert domain ID to domain with overflow check
        if (domainID > type(uint32).max) {
            revert DomainIdTooLarge(domainID);
        }
        domain = uint32(domainID);

        // Use pre-decoded source chain prover address as recipient
        recipient = sourceChainProver;

        message = encodedProofs;
    }
}
