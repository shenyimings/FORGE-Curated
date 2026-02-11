// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "../src/Permit3.sol";

import "../src/interfaces/INonceManager.sol";
import "../src/interfaces/IPermit3.sol";

// Mock token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}

/**
 * @title Permit3WitnessTest
 * @notice Tests for Permit3 witness functionality
 */
contract Permit3WitnessTest is Test {
    using ECDSA for bytes32;

    Permit3 permit3;
    MockToken token;

    uint256 ownerPrivateKey;
    address owner;
    address spender;
    address recipient;

    bytes32 constant SALT = bytes32(uint256(0));
    uint160 constant AMOUNT = 1000;
    uint48 constant EXPIRATION = 1000;
    uint48 constant NOW = 1000;

    // Witness data for testing
    bytes32 constant WITNESS = bytes32(uint256(0xDEADBEEF));
    string constant WITNESS_TYPE_STRING = "bytes32 witnessData)";
    string constant INVALID_WITNESS_TYPE_STRING = "bytes32 witnessData"; // Missing closing parenthesis

    bytes32 constant SIGNED_PERMIT3_WITNESS_TYPEHASH = keccak256(
        "SignedPermit3Witness(address owner,bytes32 salt,uint48 deadline,uint48 timestamp,bytes32 permitHash,bytes32 witnessTypeHash,bytes32 witness)"
    );

    function setUp() public {
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

    function test_validateWitnessTypeString() public {
        // This should revert with InvalidWitnessTypeString
        vm.expectRevert(
            abi.encodeWithSelector(INonceManager.InvalidWitnessTypeString.selector, INVALID_WITNESS_TYPE_STRING)
        );
        permit3.permitWitness(
            owner,
            SALT,
            uint48(block.timestamp + 1 hours),
            uint48(block.timestamp),
            _createBasicTransferPermit().permits,
            WITNESS,
            INVALID_WITNESS_TYPE_STRING,
            new bytes(65)
        );
    }

    function test_permitWitness() public {
        // Create the permit
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        // Reset recipient balance
        deal(address(token), recipient, 0);

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature =
            _signWitnessPermit(chainPermits, deadline, timestamp, SALT, WITNESS, WITNESS_TYPE_STRING);

        // Execute permit
        permit3.permitWitness(
            owner, SALT, deadline, timestamp, chainPermits.permits, WITNESS, WITNESS_TYPE_STRING, signature
        );

        // Verify transfer happened
        assertEq(token.balanceOf(recipient), AMOUNT);

        // Verify nonce is used
        assertTrue(permit3.isNonceUsed(owner, SALT));
    }

    function test_permitWitnessExpired() public {
        // Create the permit
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        // Set deadline in the past
        uint48 deadline = uint48(block.timestamp - 1);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature =
            _signWitnessPermit(chainPermits, deadline, timestamp, SALT, WITNESS, WITNESS_TYPE_STRING);

        vm.expectRevert(
            abi.encodeWithSelector(INonceManager.SignatureExpired.selector, deadline, uint48(block.timestamp))
        );
        permit3.permitWitness(
            owner, SALT, deadline, timestamp, chainPermits.permits, WITNESS, WITNESS_TYPE_STRING, signature
        );
    }

    function test_permitWitnessWrongChain() public {
        // Create the permit with wrong chain ID
        IPermit3.ChainPermits memory chainPermits = _createWrongChainTransferPermit();

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature =
            _signWitnessPermit(chainPermits, deadline, timestamp, SALT, WITNESS, WITNESS_TYPE_STRING);

        // Should revert with InvalidSignature (signature was created for wrong chain ID)
        vm.expectRevert();
        permit3.permitWitness(
            owner, SALT, deadline, timestamp, chainPermits.permits, WITNESS, WITNESS_TYPE_STRING, signature
        );
    }

    // Helper struct for invalid signature test
    struct InvalidSignatureVars {
        IPermit3.ChainPermits chainPermits;
        uint48 deadline;
        uint48 timestamp;
        bytes32 permitDataHash;
        bytes32 typeHash;
        bytes32 structHash;
        bytes32 digest;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes signature;
    }

    function test_permitWitnessInvalidSignature() public {
        InvalidSignatureVars memory vars;

        // Create the permit
        vars.chainPermits = _createBasicTransferPermit();

        vars.deadline = uint48(block.timestamp + 1 hours);
        vars.timestamp = uint48(block.timestamp);

        // Create invalid signature by signing with wrong key
        // Get hash of permits data
        vars.permitDataHash = permit3.hashChainPermits(vars.chainPermits);

        // Compute witness-specific typehash
        vars.typeHash = keccak256(abi.encodePacked(permit3.PERMIT_WITNESS_TYPEHASH_STUB(), WITNESS_TYPE_STRING));

        // Compute the structured hash
        vars.structHash = keccak256(
            abi.encode(vars.typeHash, vars.permitDataHash, owner, SALT, vars.deadline, vars.timestamp, WITNESS)
        );

        // Get the EIP-712 digest
        vars.digest = _hashTypedDataV4(vars.structHash);

        // Sign with wrong key
        (vars.v, vars.r, vars.s) = vm.sign(0x5678, vars.digest); // Wrong private key
        vars.signature = abi.encodePacked(vars.r, vars.s, vars.v);

        // When signature is from wrong private key, the recovered signer will be different
        vm.expectRevert();
        permit3.permitWitness(
            owner,
            SALT,
            vars.deadline,
            vars.timestamp,
            vars.chainPermits.permits,
            WITNESS,
            WITNESS_TYPE_STRING,
            vars.signature
        );
    }

    function test_permitWitnessAllowance() public {
        // Create allowance permit
        IPermit3.ChainPermits memory chainPermits = _createAllowancePermit();

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature =
            _signWitnessPermit(chainPermits, deadline, timestamp, SALT, WITNESS, WITNESS_TYPE_STRING);

        permit3.permitWitness(
            owner, SALT, deadline, timestamp, chainPermits.permits, WITNESS, WITNESS_TYPE_STRING, signature
        );

        // Verify allowance was set
        (uint160 allowance,,) = permit3.allowance(owner, address(token), spender);
        assertEq(allowance, AMOUNT);

        // Use allowance
        vm.prank(spender);
        permit3.transferFrom(owner, recipient, AMOUNT / 2, address(token));

        // Verify transfer and allowance decrease
        assertEq(token.balanceOf(recipient), AMOUNT / 2);
        (allowance,,) = permit3.allowance(owner, address(token), spender);
        assertEq(allowance, AMOUNT / 2);
    }

    function test_permitWitnessDifferentWitnesses() public {
        // First transfer with witness1
        {
            IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();
            bytes32 salt = bytes32(uint256(1));
            bytes32 witness = bytes32(uint256(0xDEADBEEF));

            uint48 deadline = uint48(block.timestamp + 1 hours);
            uint48 timestamp = uint48(block.timestamp);
            bytes memory signature =
                _signWitnessPermit(chainPermits, deadline, timestamp, salt, witness, WITNESS_TYPE_STRING);

            permit3.permitWitness(
                owner, salt, deadline, timestamp, chainPermits.permits, witness, WITNESS_TYPE_STRING, signature
            );
        }

        // Second transfer with different witness
        {
            IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();
            bytes32 salt = bytes32(uint256(2));
            bytes32 witness = bytes32(uint256(0xBEEFDEAD));

            uint48 deadline = uint48(block.timestamp + 1 hours);
            uint48 timestamp = uint48(block.timestamp);
            bytes memory signature =
                _signWitnessPermit(chainPermits, deadline, timestamp, salt, witness, WITNESS_TYPE_STRING);

            permit3.permitWitness(
                owner, salt, deadline, timestamp, chainPermits.permits, witness, WITNESS_TYPE_STRING, signature
            );
        }

        // Verify both transfers occurred (should be 2000 total)
        assertEq(token.balanceOf(recipient), AMOUNT * 2);
    }

    // Test cross-chain witness functionality with UnbalancedProofs
    function test_permitWitnessCrossChain() public {
        // Set specific values to ensure consistent calculation
        vm.warp(1000); // Set specific timestamp for reproducible results

        // Create unbalanced permit proof
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();
        bytes32[] memory nodes = new bytes32[](2);
        nodes[0] = bytes32(uint256(0x1234));
        nodes[1] = bytes32(uint256(0x9abc));

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        // Use our proper signing function for unbalanced proofs
        bytes memory signature =
            _signWitnessUnbalancedPermit(chainPermits, nodes, deadline, timestamp, SALT, WITNESS, WITNESS_TYPE_STRING);

        // Execute cross-chain permit
        permit3.permitWitness(
            owner, SALT, deadline, timestamp, chainPermits, nodes, WITNESS, WITNESS_TYPE_STRING, signature
        );

        // Verify transfer happened
        assertEq(token.balanceOf(recipient), AMOUNT);

        // Verify nonce is used
        assertTrue(permit3.isNonceUsed(owner, SALT));
    }

    // Helper Functions

    function _createBasicTransferPermit() internal view returns (IPermit3.ChainPermits memory) {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: 0, // Immediate transfer
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: recipient,
            amountDelta: AMOUNT
        });

        return IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });
    }

    function _createWrongChainTransferPermit() internal pure returns (IPermit3.ChainPermits memory) {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: 0, // Immediate transfer
            tokenKey: bytes32(0), // Doesn't matter for this test
            account: address(0),
            amountDelta: AMOUNT
        });

        return IPermit3.ChainPermits({
            chainId: 1, // Wrong chain ID
            permits: permits
        });
    }

    function _createAllowancePermit() internal view returns (IPermit3.ChainPermits memory) {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: EXPIRATION, // Set expiration for allowance
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: spender,
            amountDelta: AMOUNT
        });

        return IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });
    }

    // Helper struct for signing witness permits
    struct WitnessPermitVars {
        bytes32 permitDataHash;
        bytes32 typeHash;
        bytes32 structHash;
        bytes32 digest;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function _signWitnessPermit(
        IPermit3.ChainPermits memory chainPermits,
        uint48 deadline,
        uint48 timestamp,
        bytes32 salt,
        bytes32 witness,
        string memory witnessTypeString
    ) internal view returns (bytes memory) {
        WitnessPermitVars memory vars;

        // Get hash of permits data
        vars.permitDataHash = permit3.hashChainPermits(chainPermits);

        // Compute witness-specific typehash
        vars.typeHash = keccak256(abi.encodePacked(permit3.PERMIT_WITNESS_TYPEHASH_STUB(), witnessTypeString));

        // Compute the structured hash
        vars.structHash =
            keccak256(abi.encode(vars.typeHash, owner, salt, deadline, timestamp, vars.permitDataHash, witness));

        // Get the EIP-712 digest
        vars.digest = _hashTypedDataV4(vars.structHash);

        // Sign the digest
        (vars.v, vars.r, vars.s) = vm.sign(ownerPrivateKey, vars.digest);
        return abi.encodePacked(vars.r, vars.s, vars.v);
    }

    // Helper struct to avoid stack too deep errors
    struct UnbalancedWitnessVars {
        bytes32 currentChainHash;
        bytes32 merkleRoot;
        bytes32 typeHash;
        bytes32 structHash;
        bytes32 digest;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function _signWitnessUnbalancedPermit(
        IPermit3.ChainPermits memory permits,
        bytes32[] memory proof,
        uint48 deadline,
        uint48 timestamp,
        bytes32 salt,
        bytes32 witness,
        string memory witnessTypeString
    ) internal view returns (bytes memory) {
        UnbalancedWitnessVars memory vars;

        // Calculate the unbalanced root the same way the contract would
        vars.currentChainHash = _hashChainPermits(permits);

        // In the new simple structure, calculate merkle root using the proof
        // Using OpenZeppelin's MerkleProof directly
        vars.merkleRoot = MerkleProof.processProof(proof, vars.currentChainHash);

        // Compute witness-specific typehash
        vars.typeHash = keccak256(abi.encodePacked(permit3.PERMIT_WITNESS_TYPEHASH_STUB(), witnessTypeString));

        // Compute the structured hash exactly as the contract would
        vars.structHash =
            keccak256(abi.encode(vars.typeHash, owner, salt, deadline, timestamp, vars.merkleRoot, witness));

        // Get the EIP-712 digest
        vars.digest = _hashTypedDataV4(vars.structHash);

        // Sign the digest
        (vars.v, vars.r, vars.s) = vm.sign(ownerPrivateKey, vars.digest);
        return abi.encodePacked(vars.r, vars.s, vars.v);
    }

    function _hashChainPermits(
        IPermit3.ChainPermits memory chainPermits
    ) internal pure returns (bytes32) {
        bytes32[] memory permitHashes = new bytes32[](chainPermits.permits.length);

        for (uint256 i = 0; i < chainPermits.permits.length; i++) {
            permitHashes[i] = keccak256(
                abi.encode(
                    chainPermits.permits[i].modeOrExpiration,
                    chainPermits.permits[i].tokenKey,
                    chainPermits.permits[i].account,
                    chainPermits.permits[i].amountDelta
                )
            );
        }

        return keccak256(
            abi.encode(
                keccak256(
                    "ChainPermits(uint64 chainId,AllowanceOrTransfer[] permits)AllowanceOrTransfer(uint48 modeOrExpiration,bytes32 tokenKey,address account,uint160 amountDelta)"
                ),
                chainPermits.chainId,
                keccak256(abi.encodePacked(permitHashes))
            )
        );
    }

    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", permit3.DOMAIN_SEPARATOR(), structHash));
    }
}
