// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemver} from "./ISemver.sol";

/**
 * @title IProver
 * @notice Interface for proving intent fulfillment
 * @dev Defines required functionality for proving intent execution with different
 * proof mechanisms (storage or Hyperlane)
 */
interface IProver is ISemver {
    /**
     * @notice Types of proofs that can validate intent fulfillment
     * @param Storage Traditional storage-based proof mechanism
     * @param Hyperlane Proof using Hyperlane's cross-chain messaging
     */
    enum ProofType {
        Storage,
        Hyperlane
    }

    /**
     * @notice Emitted when an intent is successfully proven
     * @param _hash Hash of the proven intent
     * @param _claimant Address eligible to claim the intent's rewards
     */
    event IntentProven(bytes32 indexed _hash, address indexed _claimant);

    /**
     * @notice Gets the proof mechanism type used by this prover
     * @return ProofType enum indicating the prover's mechanism
     */
    function getProofType() external pure returns (ProofType);

    /**
     * @notice Gets the address eligible to claim rewards for a proven intent
     * @param intentHash Hash of the intent to query
     * @return Address of the claimant, or zero address if unproven
     */
    function getIntentClaimant(
        bytes32 intentHash
    ) external view returns (address);
}
