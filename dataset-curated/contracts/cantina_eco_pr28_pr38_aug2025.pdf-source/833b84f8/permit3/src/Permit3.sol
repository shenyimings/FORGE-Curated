// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IPermit3 } from "./interfaces/IPermit3.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { NonceManager } from "./NonceManager.sol";
import { PermitBase } from "./PermitBase.sol";

/**
 * @title Permit3
 * @notice A cross-chain token approval and transfer system using EIP-712 signatures with merkle proofs
 * @dev Key features and components:
 * 1. Cross-chain Compatibility: Single signature can authorize operations across multiple chains
 * 2. Batched Operations: Process multiple token approvals and transfers in one transaction
 * 3. Flexible Nonce System: Non-sequential nonces for concurrent operations and gas optimization
 * 4. Time-bound Approvals: Permissions can be set to expire automatically
 * 5. EIP-712 Typed Signatures: Enhanced security through structured data signing
 * 6. Merkle Proofs: Optimized proof structure for cross-chain verification
 */
contract Permit3 is IPermit3, PermitBase, NonceManager {
    /**
     * @dev EIP-712 typehash for bundled chain permits
     * Includes nested SpendTransferPermit struct for structured token permissions
     * Used in cross-chain signature verification
     */
    bytes32 public constant CHAIN_PERMITS_TYPEHASH = keccak256(
        "ChainPermits(uint64 chainId,AllowanceOrTransfer[] permits)AllowanceOrTransfer(uint48 modeOrExpiration,address token,address account,uint160 amountDelta)"
    );

    /**
     * @dev EIP-712 typehash for the primary permit signature
     * Binds owner, deadline, and permit data hash for signature verification
     */
    bytes32 public constant SIGNED_PERMIT3_TYPEHASH =
        keccak256("Permit3(address owner,bytes32 salt,uint48 deadline,uint48 timestamp,bytes32 merkleRoot)");

    // Constants for witness type hash strings
    string public constant PERMIT_WITNESS_TYPEHASH_STUB =
        "PermitWitness(address owner,bytes32 salt,uint48 deadline,uint48 timestamp,bytes32 merkleRoot,";

    /**
     * @dev Sets up EIP-712 domain separator with protocol identifiers
     * @notice Establishes the contract's domain for typed data signing
     */
    constructor() NonceManager("Permit3", "1") { }

    /**
     * @dev Generate EIP-712 compatible hash for chain permits
     * @param chainPermits Chain-specific permit data
     * @return bytes32 Combined hash of all permit parameters
     */
    function hashChainPermits(
        ChainPermits memory chainPermits
    ) public pure returns (bytes32) {
        uint256 permitsLength = chainPermits.permits.length;
        bytes32[] memory permitHashes = new bytes32[](permitsLength);

        for (uint256 i = 0; i < permitsLength; i++) {
            permitHashes[i] = keccak256(
                abi.encode(
                    chainPermits.permits[i].modeOrExpiration,
                    chainPermits.permits[i].token,
                    chainPermits.permits[i].account,
                    chainPermits.permits[i].amountDelta
                )
            );
        }

        return keccak256(
            abi.encode(CHAIN_PERMITS_TYPEHASH, chainPermits.chainId, keccak256(abi.encodePacked(permitHashes)))
        );
    }

    /**
     * @notice Direct permit execution for ERC-7702 integration
     * @dev No signature verification - caller must be the token owner
     * @param permits Array of permit operations to execute on current chain
     */
    function permit(
        AllowanceOrTransfer[] memory permits
    ) external {
        if (permits.length == 0) {
            revert EmptyArray();
        }

        ChainPermits memory chainPermits = ChainPermits({ chainId: uint64(block.chainid), permits: permits });
        _processChainPermits(msg.sender, uint48(block.timestamp), chainPermits);
    }

    /**
     * @notice Process token approvals for a single chain
     * @dev Core permit processing function for single-chain operations
     * @param owner The token owner authorizing the permits
     * @param salt Unique value for replay protection and nonce management
     * @param deadline Timestamp limiting signature validity for security
     * @param timestamp Timestamp of the permit
     * @param permits Array of permit operations to execute
     * @param signature EIP-712 signature authorizing all permits in the batch
     */
    function permit(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        AllowanceOrTransfer[] calldata permits,
        bytes calldata signature
    ) external {
        if (owner == address(0)) {
            revert ZeroOwner();
        }
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, uint48(block.timestamp));
        }

        if (permits.length == 0) {
            revert EmptyArray();
        }

        ChainPermits memory chainPermits = ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        bytes32 signedHash = keccak256(
            abi.encode(SIGNED_PERMIT3_TYPEHASH, owner, salt, deadline, timestamp, hashChainPermits(chainPermits))
        );

        _useNonce(owner, salt);
        _verifySignature(owner, signedHash, signature);
        _processChainPermits(owner, timestamp, chainPermits);
    }

    // Helper struct to avoid stack-too-deep errors
    struct PermitParams {
        address owner;
        bytes32 salt;
        uint48 deadline;
        uint48 timestamp;
        bytes32 currentChainHash;
        bytes32 merkleRoot;
    }

    /**
     * @notice Process token approvals across multiple chains using Merkle Tree
     * @param owner Token owner authorizing the operations
     * @param salt Unique salt for replay protection
     * @param deadline Signature expiration timestamp
     * @param timestamp Timestamp of the permit
     * @param permits Permit operations for the current chain
     * @param proof Merkle proof array for verification
     * @param signature EIP-712 signature covering the entire cross-chain batch
     */
    function permit(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        ChainPermits calldata permits,
        bytes32[] calldata proof,
        bytes calldata signature
    ) external {
        if (owner == address(0)) {
            revert ZeroOwner();
        }
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, uint48(block.timestamp));
        }
        if (permits.chainId != uint64(block.chainid)) {
            revert WrongChainId(uint64(block.chainid), permits.chainId);
        }

        // Use a struct to avoid stack-too-deep errors
        PermitParams memory params;
        params.owner = owner;
        params.salt = salt;
        params.deadline = deadline;
        params.timestamp = timestamp;

        // Hash current chain's permits
        params.currentChainHash = hashChainPermits(permits);

        // Calculate the merkle root from the proof components
        // processProof performs validation internally and provides granular error messages
        params.merkleRoot = MerkleProof.processProof(proof, params.currentChainHash);

        // Verify signature with merkle root
        bytes32 signedHash = keccak256(
            abi.encode(
                SIGNED_PERMIT3_TYPEHASH, params.owner, params.salt, params.deadline, params.timestamp, params.merkleRoot
            )
        );

        _useNonce(owner, salt);
        _verifySignature(params.owner, signedHash, signature);
        _processChainPermits(params.owner, params.timestamp, permits);
    }

    /**
     * @notice Process token approvals with witness data for single chain operations
     * @dev Handles permitWitnessTransferFrom operations with dynamic witness data
     * @param owner The token owner authorizing the permits
     * @param salt Unique salt for replay protection
     * @param deadline Timestamp limiting signature validity for security
     * @param timestamp Timestamp of the permit
     * @param permits Array of permit operations to execute
     * @param witness Additional data to include in signature verification
     * @param witnessTypeString EIP-712 type definition for witness data
     * @param signature EIP-712 signature authorizing all permits with witness
     */
    function permitWitness(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        AllowanceOrTransfer[] calldata permits,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        if (owner == address(0)) {
            revert ZeroOwner();
        }
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, uint48(block.timestamp));
        }

        if (permits.length == 0) {
            revert EmptyArray();
        }

        ChainPermits memory chainPermits = ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        // Validate witness type string format
        _validateWitnessTypeString(witnessTypeString);

        // Get hash of permits data
        bytes32 permitDataHash = hashChainPermits(chainPermits);

        // Compute witness-specific typehash and signed hash
        bytes32 typeHash = _getWitnessTypeHash(witnessTypeString);
        bytes32 signedHash = keccak256(abi.encode(typeHash, owner, salt, deadline, timestamp, permitDataHash, witness));

        _useNonce(owner, salt);
        _verifySignature(owner, signedHash, signature);
        _processChainPermits(owner, timestamp, chainPermits);
    }

    // Helper struct to avoid stack-too-deep errors
    struct WitnessParams {
        address owner;
        bytes32 salt;
        uint48 deadline;
        uint48 timestamp;
        bytes32 witness;
        bytes32 currentChainHash;
        bytes32 merkleRoot;
    }

    /**
     * @notice Process permit with additional witness data for cross-chain operations
     * @param owner Token owner address
     * @param salt Unique salt for replay protection
     * @param deadline Signature expiration timestamp
     * @param timestamp Timestamp of the permit
     * @param permits Permit operations for the current chain
     * @param proof Merkle proof array for verification
     * @param witness Additional data to include in signature verification
     * @param witnessTypeString EIP-712 type definition for witness data
     * @param signature EIP-712 signature authorizing the batch
     */
    function permitWitness(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        ChainPermits calldata permits,
        bytes32[] calldata proof,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        if (owner == address(0)) {
            revert ZeroOwner();
        }
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, uint48(block.timestamp));
        }
        if (permits.chainId != uint64(block.chainid)) {
            revert WrongChainId(uint64(block.chainid), permits.chainId);
        }

        // Validate witness type string format
        _validateWitnessTypeString(witnessTypeString);

        // Use a struct to avoid stack-too-deep errors
        WitnessParams memory params;
        params.owner = owner;
        params.salt = salt;
        params.deadline = deadline;
        params.timestamp = timestamp;
        params.witness = witness;

        // Hash current chain's permits
        params.currentChainHash = hashChainPermits(permits);

        // Calculate the merkle root
        // processProof performs validation internally and provides granular error messages
        params.merkleRoot = MerkleProof.processProof(proof, params.currentChainHash);

        // Compute witness-specific typehash and signed hash
        bytes32 typeHash = _getWitnessTypeHash(witnessTypeString);
        bytes32 signedHash = keccak256(
            abi.encode(
                typeHash,
                params.owner,
                params.salt,
                params.deadline,
                params.timestamp,
                params.merkleRoot,
                params.witness
            )
        );

        _useNonce(owner, salt);
        _verifySignature(params.owner, signedHash, signature);
        _processChainPermits(params.owner, params.timestamp, permits);
    }

    /**
     * @dev Core permit processing logic that executes multiple permit operations in a single transaction
     * @param owner Token owner authorizing the operations
     * @param timestamp Block timestamp for validation and allowance updates
     * @param chainPermits Bundle of permit operations to process on the current chain
     * @notice Handles multiple types of operations based on modeOrExpiration:
     *        = 0: Immediate transfer mode - transfers tokens directly
     *        = 1: Decrease allowance mode - reduces existing allowance
     *        = 2: Lock allowance mode - locks allowance to prevent usage
     *        = 3: Unlock allowance mode - unlocks previously locked allowance
     *        > 3: Increase allowance mode with expiration timestamp
     * @notice The function enforces timestamp-based locking mechanisms and handles
     *         special MAX_ALLOWANCE values for infinite approvals
     */
    function _processChainPermits(address owner, uint48 timestamp, ChainPermits memory chainPermits) internal {
        uint256 permitsLength = chainPermits.permits.length;
        for (uint256 i = 0; i < permitsLength; i++) {
            AllowanceOrTransfer memory p = chainPermits.permits[i];

            if (p.modeOrExpiration == uint48(PermitType.Transfer)) {
                _transferFrom(owner, p.account, p.amountDelta, p.token);
            } else {
                _processAllowanceOperation(owner, timestamp, p);
            }
        }
    }

    /**
     * @dev Processes allowance-related operations for a single permit
     * @param owner Token owner authorizing the operation
     * @param timestamp Current timestamp for validation
     * @param p The permit operation to process
     */
    function _processAllowanceOperation(address owner, uint48 timestamp, AllowanceOrTransfer memory p) private {
        if (p.token == address(0)) {
            revert ZeroToken();
        }
        if (p.account == address(0)) {
            revert ZeroAccount();
        }

        Allowance memory allowed = allowances[owner][p.token][p.account];

        // Validate lock status before processing
        _validateLockStatus(owner, p, allowed, p.modeOrExpiration, timestamp);

        // Process the operation based on its type
        if (p.modeOrExpiration == uint48(PermitType.Decrease)) {
            _decreaseAllowance(allowed, p.amountDelta);
        } else if (p.modeOrExpiration == uint48(PermitType.Lock)) {
            _lockAllowance(allowed, timestamp);
        } else if (p.modeOrExpiration == uint48(PermitType.Unlock)) {
            _unlockAllowance(allowed);
        } else {
            _processIncreaseOrUpdate(allowed, p, timestamp);
        }

        emit Permit(owner, p.token, p.account, allowed.amount, allowed.expiration, timestamp);
        allowances[owner][p.token][p.account] = allowed;
    }

    /**
     * @dev Validates if an operation can proceed based on lock status
     * @param owner Token owner
     * @param p Permit operation being processed
     * @param allowed Current allowance state
     * @param operationType Type of operation being performed
     * @param timestamp Current timestamp
     */
    function _validateLockStatus(
        address owner,
        AllowanceOrTransfer memory p,
        Allowance memory allowed,
        uint48 operationType,
        uint48 timestamp
    ) private pure {
        if (allowed.expiration == LOCKED_ALLOWANCE) {
            if (operationType == uint48(PermitType.Unlock)) {
                // Only allow unlock if timestamp is newer than lock timestamp
                if (timestamp <= allowed.timestamp) {
                    revert AllowanceLocked(owner, p.token, p.account);
                }
            } else {
                // For all other operations, reject if allowance is locked
                revert AllowanceLocked(owner, p.token, p.account);
            }
        }
    }

    /**
     * @dev Decreases an allowance, handling MAX_ALLOWANCE cases
     * @param allowed Current allowance to modify
     * @param amountDelta Amount to decrease by
     */
    function _decreaseAllowance(Allowance memory allowed, uint160 amountDelta) private pure {
        if (allowed.amount != MAX_ALLOWANCE || amountDelta == MAX_ALLOWANCE) {
            allowed.amount = amountDelta > allowed.amount ? 0 : allowed.amount - amountDelta;
        }
    }

    /**
     * @dev Locks an allowance to prevent further usage
     * @param allowed Allowance to lock
     * @param timestamp Current timestamp for lock tracking
     */
    function _lockAllowance(Allowance memory allowed, uint48 timestamp) private pure {
        allowed.amount = 0;
        allowed.expiration = LOCKED_ALLOWANCE;
        allowed.timestamp = timestamp;
    }

    /**
     * @dev Unlocks a previously locked allowance
     * @param allowed Allowance to unlock
     */
    function _unlockAllowance(
        Allowance memory allowed
    ) private pure {
        if (allowed.expiration == LOCKED_ALLOWANCE) {
            allowed.expiration = 0;
        }
    }

    /**
     * @dev Processes increase operations and updates expiration/timestamp
     * @param allowed Current allowance to modify
     * @param p Permit operation containing new values
     * @param timestamp Current timestamp
     */
    function _processIncreaseOrUpdate(
        Allowance memory allowed,
        AllowanceOrTransfer memory p,
        uint48 timestamp
    ) private pure {
        // Handle amount increase if specified
        if (p.amountDelta > 0) {
            _increaseAllowanceAmount(allowed, p.amountDelta);
        }

        // Update expiration and timestamp based on precedence rules
        _updateExpirationAndTimestamp(allowed, p.modeOrExpiration, timestamp);
    }

    /**
     * @dev Increases allowance amount, handling MAX_ALLOWANCE cases
     * @param allowed Allowance to modify
     * @param amountDelta Amount to increase by
     */
    function _increaseAllowanceAmount(Allowance memory allowed, uint160 amountDelta) private pure {
        if (allowed.amount != MAX_ALLOWANCE) {
            if (amountDelta == MAX_ALLOWANCE) {
                allowed.amount = MAX_ALLOWANCE;
            } else {
                allowed.amount += amountDelta;
            }
        }
    }

    /**
     * @dev Updates expiration and timestamp based on precedence rules
     * @param allowed Allowance to modify
     * @param newExpiration New expiration value
     * @param timestamp Current timestamp
     */
    function _updateExpirationAndTimestamp(
        Allowance memory allowed,
        uint48 newExpiration,
        uint48 timestamp
    ) private pure {
        if (timestamp > allowed.timestamp) {
            allowed.expiration = newExpiration;
            allowed.timestamp = timestamp;
        } else if (timestamp == allowed.timestamp && newExpiration > allowed.expiration) {
            allowed.expiration = newExpiration;
        }
    }

    /**
     * @dev Validates that a witness type string is properly formatted for EIP-712 compliance
     * @param witnessTypeString The EIP-712 type string to validate
     * @notice This function ensures:
     *         - The string is not empty
     *         - The string ends with a closing parenthesis ')'
     * @notice Reverts with InvalidWitnessTypeString() if validation fails
     */
    function _validateWitnessTypeString(
        string calldata witnessTypeString
    ) internal pure {
        // Validate minimum length
        if (bytes(witnessTypeString).length == 0) {
            revert InvalidWitnessTypeString(witnessTypeString);
        }

        // Validate proper ending with closing parenthesis
        uint256 witnessTypeStringLength = bytes(witnessTypeString).length;
        if (bytes(witnessTypeString)[witnessTypeStringLength - 1] != ")") {
            revert InvalidWitnessTypeString(witnessTypeString);
        }
    }

    /**
     * @dev Constructs a complete witness type hash from type string and stub for EIP-712
     * @param witnessTypeString The EIP-712 witness type string suffix to append
     * @return The keccak256 hash of the complete type string
     * @notice Combines PERMIT_WITNESS_TYPEHASH_STUB with the provided witnessTypeString
     *         to form a complete EIP-712 type definition, then returns its hash
     */
    function _getWitnessTypeHash(
        string calldata witnessTypeString
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PERMIT_WITNESS_TYPEHASH_STUB, witnessTypeString));
    }
}
