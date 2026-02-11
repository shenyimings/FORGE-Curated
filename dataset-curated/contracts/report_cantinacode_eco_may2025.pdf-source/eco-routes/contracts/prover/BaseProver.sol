// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IProver} from "../interfaces/IProver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AddressConverter} from "../libs/AddressConverter.sol";

/**
 * @title BaseProver
 * @notice Base implementation for intent proving contracts
 * @dev Provides core storage and functionality for tracking proven intents
 * and their claimants
 */
abstract contract BaseProver is IProver, ERC165 {
    using AddressConverter for bytes32;
    /**
     * @notice Address of the Portal contract
     * @dev Immutable to prevent unauthorized changes
     */

    address public immutable PORTAL;

    /**
     * @notice Mapping from intent hash to proof data
     * @dev Empty struct (zero claimant) indicates intent hasn't been proven
     */
    mapping(bytes32 => ProofData) internal _provenIntents;

    /**
     * @notice Get proof data for an intent
     * @param intentHash The intent hash to query
     * @return ProofData struct containing claimant and destination
     */
    function provenIntents(
        bytes32 intentHash
    ) external view returns (ProofData memory) {
        return _provenIntents[intentHash];
    }

    /**
     * @notice Initializes the BaseProver contract
     * @param portal Address of the Portal contract
     */
    constructor(address portal) {
        if (portal == address(0)) {
            revert ZeroPortal();
        }

        PORTAL = portal;
    }

    /**
     * @notice Process intent proofs from a cross-chain message
     * @param data Encoded (intentHash, claimant) pairs (without chain ID prefix)
     * @param destination Chain ID where the intent is being proven
     */
    function _processIntentProofs(
        bytes calldata data,
        uint64 destination
    ) internal {
        // If data is empty, just return early
        if (data.length == 0) return;

        // Ensure data length is multiple of 64 bytes (32 for hash + 32 for claimant)
        if (data.length % 64 != 0) {
            revert ArrayLengthMismatch();
        }

        uint256 numPairs = data.length / 64;

        for (uint256 i = 0; i < numPairs; i++) {
            uint256 offset = i * 64;

            // Extract intentHash and claimant using slice
            bytes32 intentHash = bytes32(data[offset:offset + 32]);
            bytes32 claimantBytes = bytes32(data[offset + 32:offset + 64]);

            // Check if the claimant bytes32 represents a valid Ethereum address
            if (!claimantBytes.isValidAddress()) {
                // Skip non-EVM addresses that can't be converted
                continue;
            }

            address claimant = claimantBytes.toAddress();

            // Validate claimant is not zero address
            if (claimant == address(0)) {
                continue; // Skip invalid claimants
            }

            // Skip rather than revert for already proven intents
            if (_provenIntents[intentHash].claimant != address(0)) {
                emit IntentAlreadyProven(intentHash);
            } else {
                _provenIntents[intentHash] = ProofData({
                    claimant: claimant,
                    destination: destination
                });
                emit IntentProven(intentHash, claimant, destination);
            }
        }
    }

    /**
     * @notice Challenge an intent proof if destination chain ID doesn't match
     * @dev Can be called by anyone to remove invalid proofs. This is a safety mechanism to ensure
     *      intents are only claimable when executed on their intended destination chains.
     * @param destination The intended destination chain ID
     * @param routeHash The hash of the intent's route
     * @param rewardHash The hash of the reward specification
     */
    function challengeIntentProof(
        uint64 destination,
        bytes32 routeHash,
        bytes32 rewardHash
    ) external {
        bytes32 intentHash = keccak256(
            abi.encodePacked(destination, routeHash, rewardHash)
        );

        ProofData memory proof = _provenIntents[intentHash];

        // Only challenge if proof exists and destination chain ID doesn't match
        if (proof.claimant != address(0) && proof.destination != destination) {
            delete _provenIntents[intentHash];

            emit IntentProofInvalidated(intentHash);
        }
    }

    /**
     * @notice Checks if this contract supports a given interface
     * @dev Implements ERC165 interface detection
     * @param interfaceId Interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IProver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
