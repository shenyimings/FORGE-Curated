// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IPermit } from "./IPermit.sol";

/**
 * @title INonceManager
 * @notice Interface for managing non-sequential nonces used in permit operations
 */
interface INonceManager is IPermit {
    /**
     * @notice Error when the merkle proof verification fails
     */
    error InvalidMerkleProof();

    /**
     * @notice Error when input parameters are invalid
     */
    error InvalidParameters();

    /**
     * @notice Thrown when a signature has expired
     * @param deadline The timestamp when the signature expired
     * @param currentTimestamp The current block timestamp
     */
    error SignatureExpired(uint48 deadline, uint48 currentTimestamp);

    /**
     * @notice Thrown when a signature is invalid
     * @param signer The address whose signature failed verification
     */
    error InvalidSignature(address signer);

    /**
     * @notice Thrown when a nonce has already been used
     * @param owner The owner of the nonce
     * @param salt The salt value that was already used
     */
    error NonceAlreadyUsed(address owner, bytes32 salt);

    /**
     * @notice Thrown when a chain ID is invalid
     */
    error WrongChainId(uint256 expected, uint256 provided);

    /**
     * @notice Thrown when a witness type string is invalid
     * @param witnessTypeString The invalid witness type string provided
     */
    error InvalidWitnessTypeString(string witnessTypeString);

    /**
     * @notice Emitted when a nonce is invalidated
     * @param owner The owner of the nonce
     * @param salt The nonce salt that was invalidated
     */
    event NonceInvalidated(address indexed owner, bytes32 indexed salt);

    /**
     * @notice Nonce invalidation parameters for a specific chain
     * @param chainId Target chain identifier
     * @param salts Array of salts to mark as used
     */
    struct NoncesToInvalidate {
        uint64 chainId;
        bytes32[] salts;
    }

    /**
     * @notice Export EIP-712 domain separator
     * @return bytes32 domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Check if a nonce has been used
     * @param owner Address that owns the nonce
     * @param salt Salt value to check
     * @return true if nonce has been used
     */
    function isNonceUsed(address owner, bytes32 salt) external view returns (bool);

    /**
     * @notice Mark multiple nonces as used
     * @param salts Array of salts to invalidate
     */
    function invalidateNonces(
        bytes32[] calldata salts
    ) external;

    /**
     * @notice Mark nonces as used with signature authorization
     * @param owner Token owner address
     * @param deadline Signature expiration timestamp
     * @param salts Array of nonce salts to invalidate
     * @param signature EIP-712 signature authorizing the invalidation
     */
    function invalidateNonces(
        address owner,
        uint48 deadline,
        bytes32[] calldata salts,
        bytes calldata signature
    ) external;

    /**
     * @notice Cross-chain nonce invalidation using Merkle Tree
     * @param owner Token owner address
     * @param deadline Signature expiration timestamp
     * @param invalidations Current chain invalidation data
     * @param proof Merkle proof array for verification
     * @param signature EIP-712 signature authorizing the invalidation
     */
    function invalidateNonces(
        address owner,
        uint48 deadline,
        NoncesToInvalidate memory invalidations,
        bytes32[] memory proof,
        bytes calldata signature
    ) external;

    /**
     * @notice Generate hash for nonce invalidation data
     * @param invalidations Nonce invalidation parameters
     * @return bytes32 EIP-712 compatible hash
     */
    function hashNoncesToInvalidate(
        NoncesToInvalidate memory invalidations
    ) external pure returns (bytes32);
}
