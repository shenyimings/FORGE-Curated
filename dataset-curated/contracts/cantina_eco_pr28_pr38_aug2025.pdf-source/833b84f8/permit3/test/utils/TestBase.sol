// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Test } from "forge-std/Test.sol";

import "../../src/Permit3.sol";
import "../../src/interfaces/IPermit3.sol";

import "./TestUtils.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title TestBase
 * @notice Unified base test contract for all Permit3 tests
 * @dev Contains common setup and helper functions to reduce duplication
 */
contract TestBase is Test {
    using ECDSA for bytes32;
    using Permit3TestUtils for Permit3;

    // Contracts
    Permit3 permit3;
    MockToken token;

    // Test accounts
    uint256 ownerPrivateKey;
    address owner;
    address spender;
    address recipient;

    // Constants
    bytes32 constant SALT = bytes32(uint256(0));
    uint160 constant AMOUNT = 1000;
    uint48 constant EXPIRATION = 1000;
    uint48 constant NOW = 1000;

    // Events
    event NonceUsed(address indexed owner, bytes32 indexed salt);
    event Approval(
        address indexed owner, address indexed token, address indexed spender, uint160 amount, uint48 expiration
    );
    event Lockdown(address indexed owner, address indexed token, address indexed spender);

    function setUp() public virtual {
        vm.warp(NOW);
        permit3 = new Permit3();
        token = new MockToken();

        ownerPrivateKey = 0x1234;
        owner = vm.addr(ownerPrivateKey);
        spender = address(0x2);
        recipient = address(0x3);

        deal(address(token), owner, 10_000);
        vm.prank(owner);
        token.approve(address(permit3), type(uint256).max);
    }

    // Common helper functions
    function _getDigest(
        bytes32 structHash
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", permit3.DOMAIN_SEPARATOR(), structHash));
    }

    // Use permit3.hashChainPermits directly instead of this function

    // Create a basic transfer permit
    function _createBasicTransferPermit() internal view returns (IPermit3.ChainPermits memory) {
        return Permit3TestUtils.createTransferPermit(address(token), recipient, AMOUNT);
    }

    // Sign a permit
    function _signPermit(
        IPermit3.ChainPermits memory chainPermits,
        uint48 deadline,
        uint48 timestamp,
        bytes32 salt
    ) internal view returns (bytes memory) {
        bytes32 permitDataHash = IPermit3(address(permit3)).hashChainPermits(chainPermits);

        bytes32 signedHash =
            keccak256(abi.encode(permit3.SIGNED_PERMIT3_TYPEHASH(), owner, salt, deadline, timestamp, permitDataHash));

        bytes32 digest = _getDigest(signedHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // Sign an unbalanced permit
    function _signUnbalancedPermit(
        IPermit3.ChainPermits memory permits,
        bytes32[] memory proof,
        uint48 deadline,
        uint48 timestamp,
        bytes32 salt
    ) internal view returns (bytes memory) {
        // Calculate the current chain hash (leaf)
        bytes32 currentChainHash = IPermit3(address(permit3)).hashChainPermits(permits);

        // Calculate the merkle root using standard merkle tree logic
        bytes32 merkleRoot = currentChainHash;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            // Standard merkle ordering: smaller value first
            if (merkleRoot <= proofElement) {
                merkleRoot = keccak256(abi.encodePacked(merkleRoot, proofElement));
            } else {
                merkleRoot = keccak256(abi.encodePacked(proofElement, merkleRoot));
            }
        }

        // Create the signature
        bytes32 signedHash =
            keccak256(abi.encode(permit3.SIGNED_PERMIT3_TYPEHASH(), owner, salt, deadline, timestamp, merkleRoot));

        bytes32 digest = _getDigest(signedHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // Mock nonce manager for internal testing
    function exposed_hashTypedDataV4(
        bytes32 structHash
    ) internal view returns (bytes32) {
        return _getDigest(structHash);
    }

    // Helper for nonce invalidation struct hash
    function _getInvalidationStructHash(
        address ownerAddress,
        uint48 deadline,
        INonceManager.NoncesToInvalidate memory invalidations
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                permit3.CANCEL_PERMIT3_TYPEHASH(), ownerAddress, deadline, permit3.hashNoncesToInvalidate(invalidations)
            )
        );
    }

    // Helper for unbalanced invalidation struct hash
    function _getUnbalancedInvalidationStructHash(
        address ownerAddress,
        uint48 deadline,
        INonceManager.NoncesToInvalidate memory invalidations,
        bytes32[] memory proof
    ) internal view returns (bytes32) {
        // For tests, manually calculate what the library would calculate
        // since we can't call library functions on memory structs
        bytes32 invalidationsHash = permit3.hashNoncesToInvalidate(invalidations);
        // Calculate merkle root from proof
        bytes32 merkleRoot = invalidationsHash;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (merkleRoot <= proofElement) {
                merkleRoot = keccak256(abi.encodePacked(merkleRoot, proofElement));
            } else {
                merkleRoot = keccak256(abi.encodePacked(proofElement, merkleRoot));
            }
        }
        return keccak256(abi.encode(permit3.CANCEL_PERMIT3_TYPEHASH(), ownerAddress, deadline, merkleRoot));
    }

    // Helper struct for witness tests
    struct WitnessTestParams {
        bytes32 salt;
        uint48 deadline;
        uint48 timestamp;
        IPermit3.ChainPermits chainPermits;
        bytes32 witness;
        string witnessTypeString;
        bytes signature;
    }

    // Helper struct for nonce invalidation tests to avoid stack too deep
    struct WithProofParams {
        bytes32 testSalt;
        bytes32[] salts;
        INonceManager.NoncesToInvalidate invalidations;
        bytes32 merkleRoot;
        bytes32[] proof;
        uint48 deadline;
        bytes32 invalidationsHash;
        bytes32 signedHash;
        bytes32 digest;
        bytes signature;
    }

    // Helper function for witness signing
    function _signWitnessPermit(
        IPermit3.ChainPermits memory chainPermits,
        bytes32 witness,
        string memory witnessTypeString,
        uint48 deadline,
        uint48 timestamp,
        bytes32 salt
    ) internal view returns (bytes memory) {
        bytes32 permitDataHash = IPermit3(address(permit3)).hashChainPermits(chainPermits);

        // Get witness type hash
        bytes32 typeHash = keccak256(abi.encodePacked(permit3.PERMIT_WITNESS_TYPEHASH_STUB(), witnessTypeString));

        // Create signed hash
        bytes32 signedHash = keccak256(abi.encode(typeHash, owner, salt, deadline, timestamp, permitDataHash, witness));

        bytes32 digest = _getDigest(signedHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
