// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MessageBridgeProver} from "./MessageBridgeProver.sol";
import {Semver} from "../libs/Semver.sol";
import {AddressConverter} from "../libs/AddressConverter.sol";
import {
    IRouterClient
} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {
    IAny2EVMMessageReceiver
} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {
    Client
} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title CCIPProver
 * @notice Prover implementation using Chainlink CCIP (Cross-Chain Interoperability Protocol)
 * @dev Extends MessageBridgeProver to send and receive intent proofs across chains via CCIP
 */
contract CCIPProver is MessageBridgeProver, IAny2EVMMessageReceiver, Semver {
    using AddressConverter for bytes32;
    using AddressConverter for address;

    /// @notice The CCIP proof type identifier
    string public constant PROOF_TYPE = "CCIP";

    /// @notice The CCIP Router contract address
    address public immutable ROUTER;

    /// @notice Struct to reduce stack depth when unpacking calldata
    /// @param sourceChainProver The address of the prover on the source chain (as bytes32)
    /// @param gasLimit The gas limit for execution on the destination chain
    struct UnpackedData {
        address sourceChainProver;
        uint256 gasLimit;
    }

    /**
     * @notice Constructs a new CCIPProver
     * @param router The CCIP Router contract address
     * @param portal The portal contract address
     * @param provers Array of whitelisted prover addresses (as bytes32)
     * @param minGasLimit Minimum gas limit for cross-chain messages (0 for default 200k)
     */
    constructor(
        address router,
        address portal,
        bytes32[] memory provers,
        uint256 minGasLimit
    ) MessageBridgeProver(portal, provers, minGasLimit) {
        if (router == address(0)) revert MessengerContractCannotBeZeroAddress();
        ROUTER = router;
    }

    /**
     * @notice Checks if this contract supports a given interface
     * @dev Overrides to include IAny2EVMMessageReceiver for CCIP compatibility
     * @param interfaceId Interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice Receives cross-chain messages from CCIP
     * @dev Only callable by the CCIP Router. Implements IAny2EVMMessageReceiver
     * @param message The CCIP message containing sender, data, and metadata
     */
    function ccipReceive(
        Client.Any2EVMMessage calldata message
    ) external only(ROUTER) {
        // Verify source chain selector is not zero
        if (message.sourceChainSelector == 0) {
            revert MessageOriginChainDomainIDCannotBeZero();
        }

        // Decode sender from bytes to address, then convert to bytes32
        address sender = abi.decode(message.sender, (address));

        // Verify sender address is not zero
        if (sender == address(0)) revert MessageSenderCannotBeZeroAddress();

        // Handle the cross-chain message using base contract functionality
        _handleCrossChainMessage(sender.toBytes32(), message.data);
    }

    /**
     * @notice Dispatches a cross-chain message via CCIP
     * @dev Internal function called by the base contract's prove() function
     * @dev CCIP has a maximum data payload size and a message execution gas limit.
     *      At time of writing, these are 30KB and 3,000,000 gas respectively.
     *      Please check CCIP's documentation for the most up-to-date values.
     * @param domainID The destination chain selector (CCIP uses this as destinationChainSelector)
     * @param encodedProofs The encoded proof data to send
     * @param data Additional data containing source chain prover and gas configuration
     * @param fee The fee amount (in native token) to pay for the cross-chain message
     */
    function _dispatchMessage(
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes calldata data,
        uint256 fee
    ) internal override {
        // Unpack the additional data
        UnpackedData memory unpacked = _unpackData(data);

        // Format the CCIP message
        Client.EVM2AnyMessage memory ccipMessage = _formatCCIPMessage(
            unpacked.sourceChainProver,
            encodedProofs,
            unpacked.gasLimit
        );

        // Send the message via CCIP Router
        IRouterClient(ROUTER).ccipSend{value: fee}(domainID, ccipMessage);
    }

    /**
     * @notice Calculates the fee required to send a cross-chain message
     * @dev Public function to query fees before sending
     * @param domainID The destination chain selector
     * @param encodedProofs The encoded proof data to send
     * @param data Additional data containing source chain prover and gas configuration
     * @return The fee amount (in native token) required
     */
    function fetchFee(
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes calldata data
    ) public view override returns (uint256) {
        // Unpack the additional data
        UnpackedData memory unpacked = _unpackData(data);

        // Format the CCIP message
        Client.EVM2AnyMessage memory ccipMessage = _formatCCIPMessage(
            unpacked.sourceChainProver,
            encodedProofs,
            unpacked.gasLimit
        );

        // Query the fee from CCIP Router
        return IRouterClient(ROUTER).getFee(domainID, ccipMessage);
    }

    /**
     * @notice Unpacks the encoded data into structured format
     * @dev Internal helper to avoid stack too deep errors
     * @dev Enforces minimum gas limit to prevent underfunded transactions
     * @param data The encoded data containing source chain prover and gas configuration
     * @return unpacked The unpacked data struct with validated gas limit
     */
    function _unpackData(
        bytes calldata data
    ) internal view returns (UnpackedData memory unpacked) {
        // Decode: (sourceChainProver, gasLimit)
        (
            unpacked.sourceChainProver,
            unpacked.gasLimit
        ) = abi.decode(data, (address, uint256));

        // Enforce minimum gas limit to prevent underfunded transactions
        if (unpacked.gasLimit < MIN_GAS_LIMIT) {
            unpacked.gasLimit = MIN_GAS_LIMIT;
        }
    }

    /**
     * @notice Formats a CCIP message for sending
     * @dev Internal helper to construct the EVM2AnyMessage struct
     * @dev Out-of-order execution is always enabled for optimal performance
     * @param sourceChainProver The prover address on the source chain
     * @param encodedProofs The proof data payload
     * @param gasLimit The gas limit for execution
     * @return ccipMessage The formatted CCIP message
     */
    function _formatCCIPMessage(
        address sourceChainProver,
        bytes calldata encodedProofs,
        uint256 gasLimit
    ) internal pure returns (Client.EVM2AnyMessage memory ccipMessage) {
        // Construct the CCIP message
        ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(sourceChainProver),
            data: encodedProofs,
            tokenAmounts: new Client.EVMTokenAmount[](0), // No token transfers
            feeToken: address(0), // Pay fees in native token
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: gasLimit,
                    allowOutOfOrderExecution: true // Always allow out-of-order execution
                })
            )
        });
    }

    /**
     * @notice Returns the proof type identifier
     * @return The proof type string
     */
    function getProofType() external pure override returns (string memory) {
        return PROOF_TYPE;
    }
}
