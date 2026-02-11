// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {HyperProver} from "../../contracts/prover/HyperProver.sol";
import {MetaProver} from "../../contracts/prover/MetaProver.sol";
import {LayerZeroProver} from "../../contracts/prover/LayerZeroProver.sol";
import {TestProver} from "../../contracts/test/TestProver.sol";
import {TestMessageBridgeProver} from "../../contracts/test/TestMessageBridgeProver.sol";
import {IProver} from "../../contracts/interfaces/IProver.sol";
import {IMessageBridgeProver} from "../../contracts/interfaces/IMessageBridgeProver.sol";

contract ProverInterfaceTest is Test {
    TestProver testProver;
    TestMessageBridgeProver testMessageBridgeProver;

    function setUp() public {
        address portal = makeAddr("portal");
        testProver = new TestProver(portal);

        bytes32[] memory whitelistedProvers = new bytes32[](1);
        whitelistedProvers[0] = bytes32(uint256(uint160(makeAddr("prover"))));
        testMessageBridgeProver = new TestMessageBridgeProver(
            portal,
            whitelistedProvers,
            200000
        );
    }

    // Helper function to encode proofs with chain ID prefix
    function encodeProofsWithChainId(
        bytes32[] memory intentHashes,
        bytes32[] memory claimants
    ) internal view returns (bytes memory) {
        require(intentHashes.length == claimants.length, "Length mismatch");

        bytes memory encodedProofs = new bytes(8 + intentHashes.length * 64);
        uint64 chainId = uint64(block.chainid);

        assembly {
            // Store chain ID in first 8 bytes
            mstore(add(encodedProofs, 0x20), shl(192, chainId))
        }

        for (uint256 i = 0; i < intentHashes.length; i++) {
            assembly {
                let offset := add(8, mul(i, 64))
                mstore(
                    add(add(encodedProofs, 0x20), offset),
                    mload(add(intentHashes, add(0x20, mul(i, 32))))
                )
                mstore(
                    add(add(encodedProofs, 0x20), add(offset, 32)),
                    mload(add(claimants, add(0x20, mul(i, 32))))
                )
            }
        }

        return encodedProofs;
    }

    function testProverInterface() public {
        // Test encoding proofs
        bytes32[] memory intentHashes = new bytes32[](2);
        bytes32[] memory claimants = new bytes32[](2);

        intentHashes[0] = keccak256("intent1");
        intentHashes[1] = keccak256("intent2");
        claimants[0] = bytes32(uint256(uint160(makeAddr("claimant1"))));
        claimants[1] = bytes32(uint256(uint160(makeAddr("claimant2"))));

        // Encode proofs with chain ID prefix
        bytes memory encodedProofs = encodeProofsWithChainId(
            intentHashes,
            claimants
        );

        // Test that we can call prove with new interface
        testProver.prove(makeAddr("sender"), 1, encodedProofs, "");

        // Verify the prove call was tracked
        (
            address sender,
            uint256 sourceChainId,
            bytes memory data,
            uint256 value
        ) = testProver.args();
        assertEq(sender, makeAddr("sender"));
        assertEq(sourceChainId, 1);
        assertEq(data, "");
        assertEq(value, 0);
        assertEq(testProver.proveCallCount(), 1);

        // Verify the proofs were processed correctly by checking proven intents
        TestProver.ProofData memory proof1 = testProver.provenIntents(
            intentHashes[0]
        );
        TestProver.ProofData memory proof2 = testProver.provenIntents(
            intentHashes[1]
        );

        assertEq(proof1.claimant, address(uint160(uint256(claimants[0]))));
        assertEq(proof2.claimant, address(uint160(uint256(claimants[1]))));
        assertEq(proof1.destination, 1);
        assertEq(proof2.destination, 1);
    }

    function testFetchFeeInterface() public {
        bytes memory encodedProofs = new bytes(64); // 1 pair
        bytes memory data = abi.encode(
            bytes32(uint256(uint160(makeAddr("sourceProver"))))
        );

        uint256 fee = testMessageBridgeProver.fetchFee(1, encodedProofs, data);
        assertEq(fee, 100000); // Default fee amount
    }

    function testGetProofType() public view {
        assertEq(testProver.getProofType(), "storage");
        assertEq(
            testMessageBridgeProver.getProofType(),
            "TestMessageBridgeProver"
        );
    }

    // Edge Case Tests

    function testProveWithInvalidEncodingLength() public {
        // Test with 8 + 65 bytes (chain ID + invalid proof length)
        bytes memory invalidProofs = new bytes(8 + 65);
        uint64 chainId = uint64(block.chainid);
        assembly {
            mstore(add(invalidProofs, 0x20), shl(192, chainId))
        }

        vm.expectRevert(IProver.ArrayLengthMismatch.selector);
        testProver.prove(makeAddr("sender"), 1, invalidProofs, "");

        // Test with 8 + 63 bytes
        invalidProofs = new bytes(8 + 63);
        assembly {
            mstore(add(invalidProofs, 0x20), shl(192, chainId))
        }
        vm.expectRevert(IProver.ArrayLengthMismatch.selector);
        testProver.prove(makeAddr("sender"), 1, invalidProofs, "");

        // Test with just 7 bytes (less than chain ID)
        invalidProofs = new bytes(7);
        vm.expectRevert(IMessageBridgeProver.InvalidProofMessage.selector);
        testProver.prove(makeAddr("sender"), 1, invalidProofs, "");
    }

    function testProveWithInvalidClaimantAddress() public {
        // Create encoded proofs with invalid claimant (not a valid address format)
        bytes memory encodedProofs = new bytes(8 + 64);
        bytes32 intentHash = keccak256("intent1");
        // Use a claimant with high bytes set to make it invalid
        bytes32 invalidClaimant = 0x0000000100000000000000000000000000000000000000000000000000000001;

        uint64 chainId = uint64(block.chainid);
        assembly {
            mstore(add(encodedProofs, 0x20), shl(192, chainId))
            mstore(add(encodedProofs, 0x28), intentHash)
            mstore(add(encodedProofs, 0x48), invalidClaimant)
        }

        // Should succeed but skip the invalid claimant
        testProver.prove(makeAddr("sender"), 1, encodedProofs, "");

        // Verify the intent was NOT proven (skipped due to invalid claimant)
        TestProver.ProofData memory proof = testProver.provenIntents(
            intentHash
        );
        assertEq(proof.claimant, address(0));
        assertEq(proof.destination, 0);

        // Test with all zeros claimant
        invalidClaimant = bytes32(0);
        assembly {
            mstore(add(encodedProofs, 0x48), invalidClaimant)
        }

        // Should succeed but skip the zero claimant
        testProver.prove(makeAddr("sender"), 1, encodedProofs, "");

        // Verify still not proven
        proof = testProver.provenIntents(intentHash);
        assertEq(proof.claimant, address(0));
        assertEq(proof.destination, 0);
    }

    function testProveWithMalformedProofData() public {
        // Test with multiple invalid claimants in batch
        bytes32[] memory intentHashes = new bytes32[](3);
        intentHashes[0] = keccak256("intent1");
        intentHashes[1] = keccak256("intent2");
        intentHashes[2] = keccak256("intent3");

        bytes32[] memory claimants = new bytes32[](3);
        claimants[0] = bytes32(uint256(uint160(makeAddr("validClaimant"))));
        claimants[
            1
        ] = 0x0000000100000000000000000000000000000000000000000000000000000001; // Invalid - high bytes set
        claimants[2] = bytes32(uint256(uint160(makeAddr("anotherValid"))));

        // Use helper to encode with chain ID
        bytes memory encodedProofs = encodeProofsWithChainId(
            intentHashes,
            claimants
        );

        // Should succeed but skip the invalid claimant
        testProver.prove(makeAddr("sender"), 1, encodedProofs, "");

        // Verify first proof was stored
        TestProver.ProofData memory proof1 = testProver.provenIntents(
            intentHashes[0]
        );
        assertEq(proof1.claimant, address(uint160(uint256(claimants[0]))));
        assertEq(proof1.destination, 1);

        // Verify second proof was skipped (invalid claimant)
        TestProver.ProofData memory proof2 = testProver.provenIntents(
            intentHashes[1]
        );
        assertEq(proof2.claimant, address(0));
        assertEq(proof2.destination, 0);

        // Verify third proof was stored
        TestProver.ProofData memory proof3 = testProver.provenIntents(
            intentHashes[2]
        );
        assertEq(proof3.claimant, address(uint160(uint256(claimants[2]))));
        assertEq(proof3.destination, 1);
    }

    function testProveWithCrossVMClaimant() public {
        // Test with non-EVM claimant (high bytes set)
        bytes32 intentHash = keccak256("crossVMIntent");
        bytes32 crossVMClaimant = bytes32(
            uint256(
                0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000001
            )
        );

        bytes32[] memory hashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        hashes[0] = intentHash;
        claimants[0] = crossVMClaimant;

        bytes memory encodedProofs = encodeProofsWithChainId(hashes, claimants);

        // This should succeed but skip the non-EVM claimant
        testProver.prove(makeAddr("sender"), 1, encodedProofs, "");

        // Verify the intent was NOT proven (skipped due to non-EVM claimant)
        TestProver.ProofData memory proof = testProver.provenIntents(
            intentHash
        );
        assertEq(proof.claimant, address(0));
        assertEq(proof.destination, 0);
    }

    function testProveLargeProofBatch() public {
        // Test with maximum reasonable batch size (100 proofs)
        uint256 numProofs = 100;

        bytes32[] memory intentHashes = new bytes32[](numProofs);
        bytes32[] memory claimants = new bytes32[](numProofs);

        for (uint256 i = 0; i < numProofs; i++) {
            intentHashes[i] = keccak256(abi.encodePacked("intent", i));
            claimants[i] = bytes32(
                uint256(uint160(address(uint160(i + 1000))))
            );
        }

        bytes memory encodedProofs = encodeProofsWithChainId(
            intentHashes,
            claimants
        );

        // Should process all proofs successfully
        testProver.prove(makeAddr("sender"), 1, encodedProofs, "");

        // Verify a few random proofs
        bytes32 checkHash = keccak256(abi.encodePacked("intent", uint256(50)));
        TestProver.ProofData memory proof = testProver.provenIntents(checkHash);
        assertEq(proof.claimant, address(uint160(1050)));
        assertEq(proof.destination, 1);
    }
}
