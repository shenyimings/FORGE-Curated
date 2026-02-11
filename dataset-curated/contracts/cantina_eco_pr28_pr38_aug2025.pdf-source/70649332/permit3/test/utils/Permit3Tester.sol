// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/Permit3.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Permit3Tester
 * @notice Helper contract to expose internal functions for testing
 */
contract Permit3Tester is Permit3 {
    /**
     * @notice Exposes the MerkleProof.processProof function for testing
     */
    function calculateUnbalancedRoot(bytes32 leaf, bytes32[] calldata proof) external pure returns (bytes32) {
        return MerkleProof.processProof(proof, leaf);
    }

    /**
     * @notice Verifies an unbalanced proof structure
     */
    function verifyUnbalancedProof(
        bytes32 leaf,
        bytes32[] calldata proof,
        bytes32 expectedRoot
    ) external pure returns (bool) {
        return MerkleProof.verify(proof, expectedRoot, leaf);
    }

    /**
     * @notice Exposes the internal hashChainPermits function for testing
     */
    // Function removed as it's now directly available from Permit3
}
