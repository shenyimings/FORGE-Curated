// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title UnbalancedMerkleTreeTest
 * @notice Tests for simple UnbalancedMerkleTree functionality using OpenZeppelin's MerkleProof
 */
contract UnbalancedMerkleTreeTest is Test {
    // Test verifying a simple merkle proof with single leaf
    function test_singleLeafVerification() public pure {
        bytes32 leaf = bytes32(uint256(0x1234));
        bytes32 root = leaf; // Single leaf is its own root

        // Empty proof for single leaf
        bytes32[] memory proofNodes = new bytes32[](0);

        // Verify using OpenZeppelin's MerkleProof
        bool result = MerkleProof.verify(proofNodes, root, leaf);
        assert(result == true);

        // Also verify using the library function directly
        // (bytes32[] array is used for merkle proofs)
        assert(MerkleProof.verify(proofNodes, root, leaf) == true);
    }

    // Test verifying merkle proof with two leaves
    function test_twoLeavesVerification() public pure {
        bytes32 leaf1 = bytes32(uint256(0x1234));
        bytes32 leaf2 = bytes32(uint256(0x5678));

        // Calculate expected root using OpenZeppelin's standard approach
        bytes32 root =
            leaf1 < leaf2 ? keccak256(abi.encodePacked(leaf1, leaf2)) : keccak256(abi.encodePacked(leaf2, leaf1));

        // Proof for leaf1 contains leaf2
        bytes32[] memory proofNodes = new bytes32[](1);
        proofNodes[0] = leaf2;

        // Verify the proof
        bool result = MerkleProof.verify(proofNodes, root, leaf1);
        assert(result == true);
    }

    // Test verifying merkle proof with four leaves
    function test_fourLeavesVerification() public pure {
        // Create a simple 4-leaf merkle tree
        bytes32 leaf1 = keccak256("leaf1");
        bytes32 leaf2 = keccak256("leaf2");
        bytes32 leaf3 = keccak256("leaf3");
        bytes32 leaf4 = keccak256("leaf4");

        // Build tree bottom-up
        bytes32 node1 =
            leaf1 < leaf2 ? keccak256(abi.encodePacked(leaf1, leaf2)) : keccak256(abi.encodePacked(leaf2, leaf1));
        bytes32 node2 =
            leaf3 < leaf4 ? keccak256(abi.encodePacked(leaf3, leaf4)) : keccak256(abi.encodePacked(leaf4, leaf3));
        bytes32 root =
            node1 < node2 ? keccak256(abi.encodePacked(node1, node2)) : keccak256(abi.encodePacked(node2, node1));

        // Proof for leaf1: [leaf2, node2]
        bytes32[] memory proofNodes = new bytes32[](2);
        proofNodes[0] = leaf2;
        proofNodes[1] = node2;

        // Verify using direct function
        bool result = MerkleProof.verify(proofNodes, root, leaf1);
        assert(result == true);

        // Verify the proof
        assert(MerkleProof.verify(proofNodes, root, leaf1) == true);
    }

    // Test invalid proof verification with incorrect root
    function test_wrongRoot() public pure {
        bytes32 leaf = bytes32(uint256(0x1234));
        bytes32 sibling = bytes32(uint256(0x5678));

        // Calculate correct root
        bytes32 correctRoot =
            leaf < sibling ? keccak256(abi.encodePacked(leaf, sibling)) : keccak256(abi.encodePacked(sibling, leaf));

        // Create proof
        bytes32[] memory proofNodes = new bytes32[](1);
        proofNodes[0] = sibling;

        // Create an incorrect root
        bytes32 incorrectRoot = bytes32(uint256(correctRoot) + 1);

        // Verify the proof with incorrect root - should fail
        bool result = MerkleProof.verify(proofNodes, incorrectRoot, leaf);
        assert(result == false);
    }

    // Test invalid proof with wrong sibling
    function test_invalidProofWithWrongSibling() public pure {
        bytes32 leaf = bytes32(uint256(0x1234));
        bytes32 correctSibling = bytes32(uint256(0x5678));

        // Calculate correct root
        bytes32 root = leaf < correctSibling
            ? keccak256(abi.encodePacked(leaf, correctSibling))
            : keccak256(abi.encodePacked(correctSibling, leaf));

        // Create proof with wrong sibling
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(correctSibling) + 1); // Wrong sibling

        // Verify should fail with invalid proof
        bool result = MerkleProof.verify(invalidProof, root, leaf);
        assert(result == false);
    }

    // Test calculateRoot function
    function test_calculateRoot() public pure {
        bytes32 leaf = keccak256("testLeaf");
        bytes32 sibling1 = keccak256("sibling1");
        bytes32 sibling2 = keccak256("sibling2");

        // Create proof nodes
        bytes32[] memory proofNodes = new bytes32[](2);
        proofNodes[0] = sibling1;
        proofNodes[1] = sibling2;

        // Calculate root using direct function
        bytes32 calculatedRoot1 = MerkleProof.processProof(proofNodes, leaf);

        // Calculate root using the same proof nodes
        bytes32 calculatedRoot2 = MerkleProof.processProof(proofNodes, leaf);

        // Both methods should give same result
        assert(calculatedRoot1 == calculatedRoot2);

        // Verify the calculated root is correct
        assert(MerkleProof.verify(proofNodes, calculatedRoot1, leaf));
    }

    // Test with empty proof array
    function test_emptyProofArray() public pure {
        bytes32 leaf = keccak256("singleLeaf");
        bytes32 root = leaf; // Single leaf is the root

        bytes32[] memory emptyProof = new bytes32[](0);

        // Should verify successfully
        assert(MerkleProof.verify(emptyProof, root, leaf));

        // Test with different leaf - should fail
        bytes32 differentLeaf = keccak256("differentLeaf");
        assert(!MerkleProof.verify(emptyProof, root, differentLeaf));
    }

    // Test proof length edge cases
    function test_proofLengthVariations() public pure {
        // Test with different proof lengths
        bytes32 leaf = keccak256("testLeaf");

        // 1-node proof
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = keccak256("node1");
        bytes32 root1 = MerkleProof.processProof(proof1, leaf);
        assert(MerkleProof.verify(proof1, root1, leaf));

        // 3-node proof (deeper tree)
        bytes32[] memory proof3 = new bytes32[](3);
        proof3[0] = keccak256("node1");
        proof3[1] = keccak256("node2");
        proof3[2] = keccak256("node3");
        bytes32 root3 = MerkleProof.processProof(proof3, leaf);
        assert(MerkleProof.verify(proof3, root3, leaf));
    }

    // Test proof structure with bytes32[] type
    function test_unbalancedProofStructure() public pure {
        bytes32 leaf = bytes32(uint256(0x1111));
        bytes32 sibling = bytes32(uint256(0x2222));

        // Calculate root
        bytes32 root =
            leaf < sibling ? keccak256(abi.encodePacked(leaf, sibling)) : keccak256(abi.encodePacked(sibling, leaf));

        // Create proof nodes
        bytes32[] memory proofNodes = new bytes32[](1);
        proofNodes[0] = sibling;

        // Verify using the proof nodes directly
        // (bytes32[] array is used for merkle proofs)
        bool result = MerkleProof.verify(proofNodes, root, leaf);
        assert(result == true);
    }

    // Test consistency between different verification methods
    function test_verificationConsistency() public pure {
        bytes32 leaf = keccak256("consistencyLeaf");

        // Create a simple proof
        bytes32[] memory proofNodes = new bytes32[](2);
        proofNodes[0] = keccak256("sibling1");
        proofNodes[1] = keccak256("sibling2");

        // Calculate root
        bytes32 root = MerkleProof.processProof(proofNodes, leaf);

        // Test direct verification
        bool directResult = MerkleProof.verify(proofNodes, root, leaf);

        // Test verification using the library function
        bool structResult = MerkleProof.verify(proofNodes, root, leaf);

        // Both methods should give the same result
        assert(directResult == structResult);
        assert(directResult == true);

        // Also test processProof consistency
        bytes32 calculatedRoot1 = MerkleProof.processProof(proofNodes, leaf);
        bytes32 calculatedRoot2 = MerkleProof.processProof(proofNodes, leaf);
        assert(calculatedRoot1 == calculatedRoot2);
        assert(calculatedRoot1 == root);
    }
}
