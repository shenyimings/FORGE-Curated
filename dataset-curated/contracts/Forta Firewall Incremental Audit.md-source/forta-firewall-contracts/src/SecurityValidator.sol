// SPDX-License-Identifier: Forta Network License
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-FN.md

pragma solidity ^0.8.25;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import "./interfaces/ISecurityValidator.sol";
import "./interfaces/Attestation.sol";

address constant BYPASS_FLAG = 0x0000000000000000000000000000000000f01274; // "forta" in leetspeak

/// @notice Attestation data wrapped for storing.
struct StoredAttestation {
    /// @notice Wrapped attestation.
    Attestation attestation;
    /// @notice The attester which signed above attestation.
    address attester;
}

/**
 * @title Validator contract used for attestations
 * @notice A singleton to be used by attesters to enable execution and contracts to ensure
 * that execution was enabled by an attester.
 */
contract SecurityValidator is ISecurityValidator, EIP712, ERC2771Context {
    using StorageSlot for bytes32;

    error AttestationOverwrite();
    error AttestationDeadlineExceeded();
    error HashCountExceeded(uint256 atIndex);
    error InvalidExecutionHash(address validator, bytes32 expectedHash, bytes32 computedHash);
    error InvalidAttestation();
    error AttestationNotFound();
    error EmptyAttestation();

    /**
     * @notice Transient storage slots used for storing the attestation values
     * and executing checkpoints
     */
    bytes32 private constant ATTESTER_SLOT = bytes32(uint256(0));
    bytes32 private constant HASH_SLOT = bytes32(uint256(1));
    bytes32 private constant HASH_COUNT_SLOT = bytes32(uint256(2));
    bytes32 private constant HASH_CACHE_INDEX_SLOT = bytes32(uint256(3));
    uint256 private constant HASH_CACHE_START_SLOT = 4;

    /// @notice Used for EIP-712 message hash calculation
    bytes32 private constant _ATTESTATION_TYPEHASH =
        keccak256("Attestation(uint256 deadline,bytes32[] executionHashes)");

    /**
     * @notice A mapping from transaction senders to first execution hashes and to attestations.
     * This is useful for storing an attestation in a previous transaction safely.
     */
    mapping(address origin => mapping(bytes32 firstExecutionHash => StoredAttestation attestation)) private attestations;

    constructor(address _trustedForwarder) EIP712("SecurityValidator", "1") ERC2771Context(_trustedForwarder) {}

    /**
     * @notice An alternative that uses persistent storage instead of transient.
     * This function defers unpacking of an attestation to the transient storage.
     * @param attestation The set of fields that correspond to and enable the execution of call(s)
     * @param attestationSignature Signature of EIP-712 message
     */
    function storeAttestation(Attestation calldata attestation, bytes calldata attestationSignature) public {
        if (attestation.executionHashes.length == 0) revert EmptyAttestation();
        bytes32 firstExecHash = attestation.executionHashes[0];
        address msgSender = _msgSender();
        StoredAttestation storage storedAttestation = attestations[msgSender][firstExecHash];
        if (storedAttestation.attestation.deadline > block.timestamp) {
            revert AttestationOverwrite();
        }
        storedAttestation.attestation = attestation;
        bytes32 structHash = hashAttestation(attestation);
        address attester = ECDSA.recover(structHash, attestationSignature);
        storedAttestation.attester = attester;
    }

    /**
     * @notice Accepts and stores an attestation to the transient storage introduced
     * with EIP-1153. Multiple contracts that operate in the same transaction can call
     * a singleton of this contract. The stored values are later used during checkpoint
     * execution.
     * @param attestation The set of fields that correspond to and enable the execution of call(s)
     * @param attestationSignature Signature of EIP-712 message
     */
    function saveAttestation(Attestation calldata attestation, bytes calldata attestationSignature) public {
        bytes32 structHash = hashAttestation(attestation);
        address attester = ECDSA.recover(structHash, attestationSignature);

        // Avoid reentrancy: Make sure that we are starting from a zero state or after
        // a previous attestation has been used.
        _requireIdleOrDone();

        _initAttestation(attestation, attester);
    }

    /// @notice Returns the attester address which attested to the current execution
    function getCurrentAttester() public view returns (address) {
        return StorageSlot.tload(ATTESTER_SLOT.asAddress());
    }

    /**
     * @notice Produces the EIP-712 hash of the attestation message.
     * @param attestation The set of fields that correspond to and enable the execution of call(s)
     */
    function hashAttestation(Attestation calldata attestation) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _ATTESTATION_TYPEHASH,
                    attestation.deadline,
                    keccak256(abi.encodePacked(attestation.executionHashes))
                )
            )
        );
    }

    /**
     * @notice Computes an execution hash by using given arbitrary checkpoint hash, msg.sender
     * and the previous execution hash. Requires the computed execution hash to be equal to
     * the currently pointed execution hash from the attestation.
     *
     * @param checkpointHash An arbitrary hash which can be computed by using variety of values
     * that occur during a call
     */
    function executeCheckpoint(bytes32 checkpointHash) public returns (bytes32) {
        bytes32 executionHash = StorageSlot.tload(HASH_SLOT.asBytes32());
        executionHash = executionHashFrom(checkpointHash, msg.sender, executionHash);

        /// If there is no actively used attestation and the bypass flag is not used,
        /// then the transaction should revert.
        bool bypassed;
        if (getCurrentAttester() == address(0)) {
            /// This can be set to zero from the trace state override.
            /// Doing the expensive read after making sure that the attester in transient storage
            /// is empty.
            bypassed = BYPASS_FLAG.code.length > 0;
        }

        // Avoid reentrancy or double init: Make sure that we are starting from a
        // zero state or after a previous attestation has been used.
        if (_idleOrDone() && !bypassed) {
            /// In case the attestation was delivered in a previous transaction, it should
            /// be loaded from here. It can be referenced by producing the first execution hash.
            executionHash = executionHashFrom(checkpointHash, msg.sender, bytes32(0));
            _tryInitAttestationFromStorage(executionHash);
            /// At this point, it is safe to continue with the first execution hash produced above.
        }

        uint256 cacheIndex = StorageSlot.tload(HASH_CACHE_INDEX_SLOT.asUint256());
        uint256 hashCount = StorageSlot.tload(HASH_COUNT_SLOT.asUint256());
        /// Current execution should not try to execute more checkpoints than attested to.
        if (!bypassed && cacheIndex >= hashCount) {
            revert HashCountExceeded(cacheIndex);
        }

        bytes32 cachedHashSlot = bytes32(cacheIndex + HASH_CACHE_START_SLOT);
        bytes32 cachedHash = StorageSlot.tload(cachedHashSlot.asBytes32());
        /// Computed hash should match with the hash that was attested to.
        if (!bypassed && executionHash != cachedHash) {
            revert InvalidExecutionHash(address(this), cachedHash, executionHash);
        }

        /// Point to the next hash from the attestation and store the latest computed
        /// hash along with the new index.
        cacheIndex++;
        StorageSlot.tstore(HASH_SLOT.asBytes32(), executionHash);
        StorageSlot.tstore(HASH_CACHE_INDEX_SLOT.asUint256(), cacheIndex);

        /// Expose the execution hash in the call output which is visible from the trace.
        return executionHash;
    }

    /**
     * @notice Makes sure that the attestation matches with current transaction
     * and all checkpoints were used correctly.
     */
    function validateFinalState() public view {
        _requireIdleOrDone();
    }

    function _initAttestation(Attestation memory attestation, address attester) internal {
        if (block.timestamp > attestation.deadline) {
            revert AttestationDeadlineExceeded();
        }

        /// Initialize and empty transient storage.
        uint256 hashCount = attestation.executionHashes.length;
        StorageSlot.tstore(ATTESTER_SLOT.asAddress(), attester);
        StorageSlot.tstore(HASH_SLOT.asBytes32(), 0);
        StorageSlot.tstore(HASH_COUNT_SLOT.asUint256(), hashCount);
        StorageSlot.tstore(HASH_CACHE_INDEX_SLOT.asUint256(), 0);

        /// Store all execution hashes.
        uint256 len = attestation.executionHashes.length;
        for (uint256 i = 0; i < len; i++) {
            bytes32 execHash = attestation.executionHashes[i];
            bytes32 currIndex = bytes32(HASH_CACHE_START_SLOT + i);
            StorageSlot.tstore(currIndex.asBytes32(), execHash);
        }
    }

    function _tryInitAttestationFromStorage(bytes32 executionHash) internal {
        StoredAttestation storage storedAttestation = attestations[tx.origin][executionHash];
        if (storedAttestation.attestation.deadline == 0) revert AttestationNotFound();
        _initAttestation(storedAttestation.attestation, storedAttestation.attester);
        delete attestations[tx.origin][executionHash];
    }

    function _idleOrDone() internal view returns (bool) {
        uint256 cacheIndex = StorageSlot.tload(HASH_CACHE_INDEX_SLOT.asUint256());
        uint256 hashCount = StorageSlot.tload(HASH_COUNT_SLOT.asUint256());
        return cacheIndex >= hashCount;
    }

    function _requireIdleOrDone() internal view {
        if (!_idleOrDone()) revert InvalidAttestation();
    }

    /**
     * @notice Computes the execution hash from given inputs.
     * @param checkpointHash An arbitrary hash which can be computed by using variety of values
     * that occur during a call
     * @param caller msg.sender of executeCheckpoint() call
     * @param executionHash Previous execution hash
     */
    function executionHashFrom(bytes32 checkpointHash, address caller, bytes32 executionHash)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(checkpointHash, caller, executionHash));
    }
}
