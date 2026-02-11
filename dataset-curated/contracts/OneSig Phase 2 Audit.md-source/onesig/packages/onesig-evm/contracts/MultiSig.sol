// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.22;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SelfCallable } from "./lib/SelfCallable.sol";

/**
 * @title MultiSig
 * @notice Abstract contract that manages a set of signers and a signature threshold.
 *         Designed to be inherited by contracts requiring multi-signature verification.
 * @dev Uses EnumerableSet to store signer addresses and ECDSA for signature recovery.
 */
abstract contract MultiSig is SelfCallable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Set of available signers for the MultiSig.
     */
    EnumerableSet.AddressSet internal signerSet;

    /**
     * @notice The number of signatures required to execute a transaction.
     */
    uint256 public threshold;

    /// @notice Error thrown when a signer address is invalid.
    error InvalidSigner();

    /// @notice Error thrown when the threshold is set to zero.
    error ZeroThreshold();

    /// @notice Error thrown when the total number of signers is less than the threshold.
    /// @param totalSigners The current number of signers.
    /// @param threshold The required threshold.
    error TotalSignersLessThanThreshold(uint256 totalSigners, uint256 threshold);

    /// @notice Error thrown when attempting to add a signer who is already active.
    /// @param signer The address of the signer.
    error SignerAlreadyAdded(address signer);

    /// @notice Error thrown when attempting to remove a signer who is not found.
    /// @param signer The address of the signer.
    error SignerNotFound(address signer);

    /// @notice Error thrown when there is a signature format error or mismatch in length.
    error SignatureError();

    /// @notice Error thrown when signers are not sorted in ascending order (prevents duplicates).
    error UnsortedSigners();

    /**
     * @notice Emitted when a signer's active status is updated.
     * @param signer The address of the signer.
     * @param active True if added, false if removed.
     */
    event SignerSet(address indexed signer, bool active);

    /**
     * @notice Emitted when the threshold for signatures is set.
     * @param threshold The new threshold.
     */
    event ThresholdSet(uint256 threshold);

    /**
     * @dev The length of a single signature in bytes (r=32, s=32, v=1).
     */
    uint8 constant SIGNATURE_LENGTH = 65;

    /**
     * @dev Initializes the MultiSig with a list of signers and sets the signature threshold.
     * @param _signers Array of signer addresses.
     * @param _threshold The initial threshold for signatures.
     */
    constructor(address[] memory _signers, uint256 _threshold) {
        for (uint256 i = 0; i < _signers.length; i++) {
            _addSigner(_signers[i]);
        }
        _setThreshold(_threshold);
    }

    /**
     * @notice Allows the MultiSig contract to update the signature threshold.
     * @dev This function can only be called by the MultiSig contract itself.
     * @param _threshold The new threshold value.
     */
    function setThreshold(uint256 _threshold) external onlySelfCall {
        _setThreshold(_threshold);
    }

    /**
     * @dev Internal function to set the threshold for this MultiSig.
     *      - The threshold must be greater than zero.
     *      - The threshold must be less than or equal to the number of signers.
     * @param _threshold The new threshold value.
     */
    function _setThreshold(uint256 _threshold) internal {
        if (_threshold == 0) revert ZeroThreshold();
        if (totalSigners() < _threshold) revert TotalSignersLessThanThreshold(totalSigners(), _threshold);

        threshold = _threshold;
        emit ThresholdSet(_threshold);
    }

    /**
     * @notice Adds or removes a signer from this MultiSig.
     * @dev Only callable via the MultiSig contract itself.
     * @param _signer The address of the signer to add/remove.
     * @param _active True to add signer, false to remove signer.
     */
    function setSigner(address _signer, bool _active) external onlySelfCall {
        if (_active) {
            _addSigner(_signer);
        } else {
            _removeSigner(_signer);
        }
    }

    /**
     * @dev Internal function to add a signer.
     *      - `address(0)` is not a valid signer.
     *      - A signer cannot be added twice.
     * @param _signer The address of the signer to add.
     */
    function _addSigner(address _signer) internal {
        if (_signer == address(0)) revert InvalidSigner();
        if (!signerSet.add(_signer)) revert SignerAlreadyAdded(_signer);

        emit SignerSet(_signer, true);
    }

    /**
     * @dev Internal function to remove a signer.
     *      - Signer must be part of the existing set of signers.
     *      - The threshold must be less than or equal to the number of remaining signers.
     * @param _signer The address of the signer to remove.
     */
    function _removeSigner(address _signer) internal {
        if (!signerSet.remove(_signer)) revert SignerNotFound(_signer);
        if (totalSigners() < threshold) revert TotalSignersLessThanThreshold(totalSigners(), threshold);

        emit SignerSet(_signer, false);
    }

    /**
     * @notice Verifies signatures on a given digest against the threshold.
     * @dev Verifies that exactly `threshold` signatures are present, sorted by ascending signer addresses.
     * @param _digest The message digest (hash) being signed.
     * @param _signatures The concatenated signatures.
     */
    function verifySignatures(bytes32 _digest, bytes calldata _signatures) public view {
        verifyNSignatures(_digest, _signatures, threshold);
    }

    /**
     * @notice Verifies N signatures on a given digest.
     * @dev Reverts if:
     *       - The threshold passed is zero.
     *       - The number of signatures doesn't match N (each signature is 65 bytes).
     *       - The signers are not strictly increasing (to prevent duplicates).
     *       - Any signer is not in the set of authorized signers.
     * @param _digest The message digest (hash) being signed.
     * @param _signatures The concatenated signatures.
     * @param _threshold The required number of valid signatures.
     */
    function verifyNSignatures(bytes32 _digest, bytes calldata _signatures, uint256 _threshold) public view {
        if (_threshold == 0) revert ZeroThreshold();
        // Each signature is SIGNATURE_LENGTH (65) bytes (r=32, s=32, v=1).
        if ((_signatures.length % SIGNATURE_LENGTH) != 0) revert SignatureError();
        uint256 signaturesCount = _signatures.length / SIGNATURE_LENGTH;
        if (signaturesCount < _threshold) revert SignatureError();

        // There cannot be a signer with address 0, so we start with address(0) to ensure ascending order.
        address lastSigner = address(0);

        for (uint256 i = 0; i < signaturesCount; i++) {
            // Extract a single signature (SIGNATURE_LENGTH (65) bytes) at a time.
            bytes calldata signature = _signatures[i * SIGNATURE_LENGTH:(i + 1) * SIGNATURE_LENGTH];
            address currentSigner = ECDSA.recover(_digest, signature);

            // Check ordering to avoid duplicates and ensure strictly increasing addresses.
            if (currentSigner <= lastSigner) revert UnsortedSigners();
            // Check if the signer is in our set.
            if (!isSigner(currentSigner)) revert SignerNotFound(currentSigner);
            lastSigner = currentSigner;
        }
    }

    /**
     * @notice Returns the list of all active signers.
     * @return An array of addresses representing the current set of signers.
     */
    function getSigners() public view returns (address[] memory) {
        return signerSet.values();
    }

    /**
     * @notice Checks if a given address is in the set of signers.
     * @param _signer The address to check.
     * @return True if the address is a signer, otherwise false.
     */
    function isSigner(address _signer) public view returns (bool) {
        return signerSet.contains(_signer);
    }

    /**
     * @notice Returns the total number of active signers.
     * @return The number of signers currently active.
     */
    function totalSigners() public view returns (uint256) {
        return signerSet.length();
    }
}
