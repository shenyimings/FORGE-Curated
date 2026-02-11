// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Test, Vm } from "forge-std/Test.sol";

import "../../src/Permit3.sol";
import "../../src/interfaces/IPermit3.sol";

/**
 * @title MockToken
 * @notice Standard mock ERC20 token for testing
 */
contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}

/**
 * @title Permit3TestUtils
 * @notice Shared utility library for Permit3 tests
 * @dev Contains common helper functions for EIP-712 signatures and data hashing
 */
library Permit3TestUtils {
    /**
     * @notice Get the EIP-712 domain separator
     * @param permit3 The Permit3 contract
     * @return The domain separator
     */
    function domainSeparator(
        Permit3 permit3
    ) internal view returns (bytes32) {
        return permit3.DOMAIN_SEPARATOR();
    }

    /**
     * @notice Hash typed data according to EIP-712
     * @param permit3 The Permit3 contract
     * @param structHash The hash of the struct data
     * @return The EIP-712 compatible message digest
     */
    function hashTypedDataV4(Permit3 permit3, bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(permit3), structHash));
    }

    /**
     * @notice Generate a signature for a digest
     * @param vm The Foundry VM instance
     * @param digest The digest to sign
     * @param privateKey The private key to sign with
     * @return The signature bytes
     */
    function signDigest(Vm vm, bytes32 digest, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Hash chain permits data
     * @param permit3 The Permit3 contract
     * @param permits The chain permits data
     * @return The hash of the chain permits
     */
    function hashChainPermits(Permit3 permit3, IPermit3.ChainPermits memory permits) internal pure returns (bytes32) {
        // This can't be pure since it requires calling a view function
        // But we're marking it as pure to avoid the warning
        return IPermit3(address(permit3)).hashChainPermits(permits);
    }

    /**
     * @notice Hash chain permits data with empty permits array
     * @param permit3 The Permit3 contract
     * @param chainId The chain ID
     * @return The hash of the chain permits with empty permits array
     */
    function hashEmptyChainPermits(Permit3 permit3, uint64 chainId) internal pure returns (bytes32) {
        IPermit3.AllowanceOrTransfer[] memory emptyPermits = new IPermit3.AllowanceOrTransfer[](0);
        IPermit3.ChainPermits memory chainPermits = IPermit3.ChainPermits({ chainId: chainId, permits: emptyPermits });

        return hashChainPermits(permit3, chainPermits);
    }

    /**
     * @notice Create a basic transfer permit
     * @param token The token address
     * @param recipient The recipient address
     * @param amount The transfer amount
     * @return ChainPermits structure with transfer data
     */
    function createTransferPermit(
        address token,
        address recipient,
        uint160 amount
    ) internal view returns (IPermit3.ChainPermits memory) {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: 0, // Immediate transfer
            token: token,
            account: recipient,
            amountDelta: amount
        });

        return IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });
    }

    /**
     * @notice Verify balanced subtree
     * @param leaf The leaf to verify
     * @param proof The merkle proof
     * @return The calculated root
     */
    function verifyBalancedSubtree(bytes32 leaf, bytes32[] memory proof) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash;
    }
}
