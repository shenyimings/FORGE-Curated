// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { INonceManager } from "./interfaces/INonceManager.sol";
import { EIP712 } from "./lib/EIP712.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title NonceManager
 * @notice Manages non-sequential nonces for replay protection in the Permit3 system
 * @dev Key features:
 * - Non-sequential nonces for concurrent operation support
 * - Signature-based nonce invalidation
 * - Cross-chain nonce management
 * - EIP-712 compliant signatures
 */
abstract contract NonceManager is INonceManager, EIP712 {
    using ECDSA for bytes32;
    using SignatureChecker for address;

    /// @dev Constant representing an unused nonce
    uint256 private constant NONCE_NOT_USED = 0;

    /// @dev Constant representing a used nonce
    uint256 private constant NONCE_USED = 1;

    /**
     * @notice Maps owner address to their used nonces
     * @dev Non-sequential nonces allow parallel operations without conflicts
     */
    mapping(address => mapping(bytes32 => uint256)) internal usedNonces;

    /**
     * @notice EIP-712 typehash for nonce invalidation
     * @dev Includes chainId for cross-chain replay protection
     */
    bytes32 public constant NONCES_TO_INVALIDATE_TYPEHASH =
        keccak256("NoncesToInvalidate(uint64 chainId,bytes32[] salts)");

    /**
     * @notice EIP-712 typehash for invalidation signatures
     * @dev Includes owner, deadline, and unbalanced root for batch operations
     */
    bytes32 public constant CANCEL_PERMIT3_TYPEHASH =
        keccak256("CancelPermit3(address owner,uint48 deadline,bytes32 merkleRoot)");

    /**
     * @notice Initialize EIP-712 domain separator
     * @param name Contract name for EIP-712 domain
     * @param version Contract version for EIP-712 domain
     */
    constructor(string memory name, string memory version) EIP712(name, version) { }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Check if a specific nonce has been used
     * @param owner The address to check nonces for
     * @param salt The salt value to verify
     * @return True if nonce has been used, false otherwise
     */
    function isNonceUsed(address owner, bytes32 salt) external view returns (bool) {
        return usedNonces[owner][salt] == NONCE_USED;
    }

    /**
     * @notice Directly invalidate multiple nonces without signature
     * @param salts Array of salts to mark as used
     */
    function invalidateNonces(
        bytes32[] calldata salts
    ) external {
        _processNonceInvalidation(msg.sender, salts);
    }

    /**
     * @notice Invalidate nonces using a signed message
     * @param owner Address that signed the invalidation
     * @param deadline Timestamp after which signature is invalid
     * @param salts Array of nonce salts to invalidate
     * @param signature EIP-712 signature authorizing invalidation
     */
    function invalidateNonces(
        address owner,
        uint48 deadline,
        bytes32[] calldata salts,
        bytes calldata signature
    ) external {
        if (owner == address(0)) {
            revert ZeroOwner();
        }
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, uint48(block.timestamp));
        }
        if (salts.length == 0) {
            revert EmptyArray();
        }

        NoncesToInvalidate memory invalidations = NoncesToInvalidate({ chainId: uint64(block.chainid), salts: salts });

        bytes32 signedHash =
            keccak256(abi.encode(CANCEL_PERMIT3_TYPEHASH, owner, deadline, hashNoncesToInvalidate(invalidations)));

        _verifySignature(owner, signedHash, signature);

        _processNonceInvalidation(owner, invalidations.salts);
    }

    /**
     * @notice Cross-chain nonce invalidation using the Unbalanced Merkle Tree approach
     * @param owner Token owner
     * @param deadline Signature expiration
     * @param proof Unbalanced Merkle Tree invalidation proof
     * @param signature Authorization signature
     */
    function invalidateNonces(
        address owner,
        uint48 deadline,
        NoncesToInvalidate calldata invalidations,
        bytes32[] calldata proof,
        bytes calldata signature
    ) external {
        if (owner == address(0)) {
            revert ZeroOwner();
        }
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, uint48(block.timestamp));
        }
        if (invalidations.chainId != uint64(block.chainid)) {
            revert WrongChainId(uint64(block.chainid), invalidations.chainId);
        }

        // Calculate the root from the invalidations and proof
        // processProof performs validation internally and provides granular error messages
        bytes32 invalidationsHash = hashNoncesToInvalidate(invalidations);
        bytes32 merkleRoot = MerkleProof.processProof(proof, invalidationsHash);

        bytes32 signedHash = keccak256(abi.encode(CANCEL_PERMIT3_TYPEHASH, owner, deadline, merkleRoot));

        _verifySignature(owner, signedHash, signature);

        _processNonceInvalidation(owner, invalidations.salts);
    }

    /**
     * @notice Generate EIP-712 hash for nonce invalidation data
     * @param invalidations Struct containing chain ID and nonces
     * @return bytes32 Hash of the invalidation data
     */
    function hashNoncesToInvalidate(
        NoncesToInvalidate memory invalidations
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(NONCES_TO_INVALIDATE_TYPEHASH, invalidations.chainId, invalidations.salts));
    }

    /**
     * @dev Process batch nonce invalidation by marking all specified nonces as used
     * @param owner Token owner whose nonces are being invalidated
     * @param salts Array of salts to invalidate
     * @notice This function iterates through all provided salts and:
     *         1. Marks each nonce as NONCE_USED in the usedNonces mapping
     *         2. Emits a NonceInvalidated event for each invalidated nonce
     * @notice This is an internal helper used by the public invalidateNonces functions
     *         to process the actual invalidation after signature verification
     */
    function _processNonceInvalidation(address owner, bytes32[] memory salts) internal {
        uint256 saltsLength = salts.length;

        require(saltsLength != 0, EmptyArray());

        for (uint256 i = 0; i < saltsLength; i++) {
            usedNonces[owner][salts[i]] = NONCE_USED;
            emit NonceInvalidated(owner, salts[i]);
        }
    }

    /**
     * @dev Consume a nonce by marking it as used for replay protection
     * @param owner Token owner whose nonce is being consumed
     * @param salt Unique salt value identifying the nonce to consume
     * @notice This function provides replay protection by:
     *         1. Checking if the nonce has already been used (NONCE_NOT_USED = 0)
     *         2. Marking the nonce as used (NONCE_USED = 1)
     * @notice Reverts with NonceAlreadyUsed() if the nonce was previously consumed
     * @notice This is called before processing permits to ensure each signature
     *         can only be used once per salt value
     */
    function _useNonce(address owner, bytes32 salt) internal {
        if (usedNonces[owner][salt] != NONCE_NOT_USED) {
            revert NonceAlreadyUsed(owner, salt);
        }
        usedNonces[owner][salt] = NONCE_USED;
    }

    /**
     * @dev Validate EIP-712 signature against expected signer using ECDSA recovery
     * @param owner Expected message signer to validate against
     * @param structHash Hash of the signed data structure (pre-hashed message)
     * @param signature Raw signature bytes in (v, r, s) format for ECDSA recovery
     * @notice This function:
     *         1. Computes the EIP-712 compliant digest using _hashTypedDataV4
     *         2. For short signatures (<=65 bytes), tries ECDSA recovery first
     *         3. Falls back to ERC-1271 validation for contract wallets or if ECDSA fails
     *         4. Handles EIP-7702 delegated EOAs correctly
     * @notice Reverts with InvalidSignature() if the signature is invalid or
     *         the recovered signer doesn't match the expected owner
     */
    function _verifySignature(address owner, bytes32 structHash, bytes calldata signature) internal view {
        bytes32 digest = _hashTypedDataV4(structHash);

        // For signatures <= 65 bytes (supporting ERC-2098 compact signatures),
        // try ECDSA recovery first before falling back to ERC-1271
        uint256 signatureLength = signature.length;
        if (signatureLength == 64 || signatureLength == 65) {
            if (digest.recover(signature) == owner) {
                return;
            }
        }

        // For longer signatures or when ECDSA failed with a contract/EIP-7702 EOA,
        // use ERC-1271 validation
        if (owner.code.length == 0 || !owner.isValidERC1271SignatureNow(digest, signature)) {
            revert InvalidSignature(owner);
        }
    }
}
