// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILayerZeroReceiver} from "../interfaces/layerzero/ILayerZeroReceiver.sol";
import {ILayerZeroEndpointV2} from "../interfaces/layerzero/ILayerZeroEndpointV2.sol";
import {MessageBridgeProver} from "./MessageBridgeProver.sol";
import {Semver} from "../libs/Semver.sol";

/**
 * @title LayerZeroProver
 * @notice Prover implementation using LayerZero's cross-chain messaging system
 * @dev Processes proof messages from LayerZero endpoint and records proven intents
 */
contract LayerZeroProver is ILayerZeroReceiver, MessageBridgeProver, Semver {
    /**
     * @notice Struct for unpacked data from _data parameter
     * @dev Contains fields decoded from the _data parameter
     */
    struct UnpackedData {
        bytes32 sourceChainProver; // Address of prover on source chain
        bytes options; // LayerZero message options
        uint256 gasLimit; // Gas limit for execution
    }

    /**
     * @notice Constant indicating this contract uses LayerZero for proving
     */
    string public constant PROOF_TYPE = "LayerZero";

    /**
     * @notice Address of local LayerZero endpoint
     */
    address public immutable ENDPOINT;

    /**
     * @notice LayerZero endpoint address cannot be zero
     */
    error EndpointCannotBeZeroAddress();

    /**
     * @notice LayerZero endpoint address cannot be zero
     */
    error DelegateCannotBeZeroAddress();

    /**
     * @notice Invalid executor address
     * @param executor The invalid executor address
     */
    error InvalidExecutor(address executor);

    /**
     * @param endpoint Address of local LayerZero endpoint
     * @param portal Address of Portal contract
     * @param provers Array of trusted prover addresses (as bytes32 for cross-VM compatibility)
     * @param minGasLimit Minimum gas limit for cross-chain messages (200k if zero)
     */
    constructor(
        address endpoint,
        address delegate,
        address portal,
        bytes32[] memory provers,
        uint256 minGasLimit
    ) MessageBridgeProver(portal, provers, minGasLimit) {
        if (endpoint == address(0)) revert EndpointCannotBeZeroAddress();
        if (delegate == address(0)) revert DelegateCannotBeZeroAddress();

        // Store the LayerZero endpoint address for future reference
        ENDPOINT = endpoint;

        // Set the delegate address on the LayerZero endpoint
        // The delegate is authorized to configure LayerZero settings on behalf of this contract
        // This includes setting configs, managing paths, and other administrative functions
        ILayerZeroEndpointV2(endpoint).setDelegate(delegate);
    }

    /**
     * @notice Handles incoming LayerZero messages containing proof data
     * @dev Processes batch updates to proven intents from valid sources
     * @param origin Origin information containing source endpoint and sender
     * param guid Unique identifier for the message (not used here)
     * @param message Encoded array of intent hashes and claimants
     * param executor Address of the executor (should be endpoint or zero)
     * param extraData Additional data for message processing (not used here)
     */
    function lzReceive(
        Origin calldata origin,
        bytes32 /* guid */,
        bytes calldata message,
        address /* executor */,
        bytes calldata /* extraData */
    ) external payable override only(ENDPOINT) {
        // Validate sender is not zero
        if (origin.sender == bytes32(0)) {
            revert MessageSenderCannotBeZeroAddress();
        }

        _handleCrossChainMessage(origin.sender, message);
    }

    /**
     * @notice Check if path is allowed for receiving messages
     * @param origin Origin information to check
     * @return Whether the origin is allowed
     */
    function allowInitializePath(
        Origin calldata origin
    ) external view override returns (bool) {
        // Check if sender is whitelisted
        return isWhitelisted(origin.sender);
    }

    /**
     * @notice Get next expected nonce from a source
     * @dev Always returns 0 as we don't track nonces
     * @return Always returns 0 as we don't track nonces
     */
    function nextNonce(
        uint32 /* srcEid */,
        bytes32 /* sender */
    ) external pure override returns (uint64) {
        // We don't track nonces, return 0
        return 0;
    }

    /**
     * @notice Implementation of message dispatch for LayerZero
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

        // Create messaging parameters for LayerZero
        ILayerZeroEndpointV2.MessagingParams
            memory params = _formatLayerZeroMessage(
                domainID,
                encodedProofs,
                unpacked
            );

        // Send the message through LayerZero endpoint
        // solhint-disable-next-line check-send-result
        ILayerZeroEndpointV2(ENDPOINT).send{value: fee}(
            params,
            msg.sender // refund address
        );
    }

    /**
     * @notice Calculates the fee required for LayerZero message dispatch
     * @dev Queries the Endpoint contract for accurate fee estimation
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
        return _fetchFee(domainID, encodedProofs, unpacked);
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
        // Create messaging parameters for LayerZero
        ILayerZeroEndpointV2.MessagingParams
            memory params = _formatLayerZeroMessage(
                domainID,
                encodedProofs,
                unpacked
            );

        // Query LayerZero endpoint for accurate fee estimate
        ILayerZeroEndpointV2.MessagingFee memory fee = ILayerZeroEndpointV2(
            ENDPOINT
        ).quote(params, address(this));

        return fee.nativeFee;
    }

    /**
     * @notice Returns the proof type used by this prover
     * @return ProofType indicating LayerZero proving mechanism
     */
    function getProofType() external pure override returns (string memory) {
        return PROOF_TYPE;
    }

    /**
     * @notice Formats data for LayerZero message dispatch with encoded proofs
     * @dev Prepares all parameters needed for the Endpoint send call
     * @param domainID Domain ID of the source chain
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param unpacked Struct containing decoded data from data parameter
     * @return params Structured dispatch parameters for LayerZero message
     */
    function _formatLayerZeroMessage(
        uint64 domainID,
        bytes calldata encodedProofs,
        UnpackedData memory unpacked
    )
        internal
        pure
        returns (ILayerZeroEndpointV2.MessagingParams memory params)
    {
        // Use domain ID directly as endpoint ID with overflow check
        if (domainID > type(uint32).max) {
            revert DomainIdTooLarge(domainID);
        }
        params.dstEid = uint32(domainID);

        // Use the source chain prover address as the message recipient
        params.receiver = unpacked.sourceChainProver;

        params.message = encodedProofs;

        // Use provided options or create default options with gas limit
        params.options = unpacked.options.length > 0
            ? unpacked.options
            : abi.encodePacked(
                uint16(3), // option type for gas limit
                unpacked.gasLimit // gas amount
            );
        params.payInLzToken = false;
    }
}
