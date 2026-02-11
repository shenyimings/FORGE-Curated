// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProver} from "./IProver.sol";

/**
 * @title IMessageBridgeProver
 * @notice Interface for message-bridge based provers
 * @dev Defines common functionality and events for cross-chain message bridge provers
 */
interface IMessageBridgeProver is IProver {
    /**
     * @notice Insufficient fee provided for cross-chain message dispatch
     * @param requiredFee Amount of fee required
     */
    error InsufficientFee(uint256 requiredFee);

    /**
     * @notice Unauthorized call detected
     *  @param expected Address that should have been the sender
     *  @param actual Address that actually sent the message
     */
    error UnauthorizedSender(address expected, address actual);

    /**
     * @notice Unauthorized incoming proof from source chain
     * @param sender Address that initiated the proof (as bytes32 for cross-VM compatibility)
     */
    error UnauthorizedIncomingProof(bytes32 sender);

    /**
     * @notice Messenger contract address cannot be zero
     * @dev MessengerContract is a general term for the message-passing contract that handles
     *      cross-chain communication, used to consolidate errors. Specific implementations'
     *      terminology will reflect that of the protocol and as such may not match up with what is
     *      used in Eco's interface contract.
     */
    error MessengerContractCannotBeZeroAddress();

    /**
     * @notice Message origin chain domain ID cannot be zero
     * @dev DomainID is a general term for the chain identifier used by cross-chain messaging protocols,
     *      used to consolidate errors. Specific implementations' terminology will reflect that of the
     *      protocol and as such may not match up with what is used in Eco's interface contract.
     */
    error MessageOriginChainDomainIDCannotBeZero();

    /**
     * @notice Message sender address cannot be zero
     */
    error MessageSenderCannotBeZeroAddress();

    /**
     * @notice message is invalid
     */
    error InvalidProofMessage();

    /**
     * @notice Calculates the fee required for message dispatch
     * @param domainID Bridge-specific domain ID of the source chain (where the intent was created).
     *        IMPORTANT: This is NOT the chain ID. Each bridge provider uses their own
     *        domain ID mapping system. You MUST check with the specific bridge provider
     *        (Hyperlane, LayerZero, Metalayer) documentation to determine the correct
     *        domain ID for the source chain.
     * @param encodedProofs Encoded (intentHash, claimant) pairs as bytes
     * @param data Additional data for message formatting.
     *        Specific format varies by implementation:
     *        - HyperProver: (bytes32 sourceChainProver, bytes metadata, address hookAddr, [uint256 gasLimitOverride])
     *        - MetaProver: (bytes32 sourceChainProver, [uint256 gasLimitOverride])
     *        - LayerZeroProver: (bytes32 sourceChainProver, bytes options, [uint256 gasLimitOverride])
     * @return Fee amount required for message dispatch
     */
    function fetchFee(
        uint64 domainID,
        bytes calldata encodedProofs,
        bytes calldata data
    ) external view returns (uint256);

    /**
     * @notice Domain ID is too large to fit in uint32
     * @param domainId The domain ID that is too large
     */
    error DomainIdTooLarge(uint64 domainId);
}
