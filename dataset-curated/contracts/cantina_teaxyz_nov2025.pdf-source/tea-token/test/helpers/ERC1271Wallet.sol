// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title ERC1271Wallet
 * @notice Secure ERC-1271 implementation with replay attack protection
 * @dev Wraps incoming digest with wallet's own EIP-712 domain to prevent 
 *      signature replay across multiple wallets owned by the same signer.
 *      See: https://www.alchemy.com/blog/erc-1271-signature-replay-vulnerability
 */
contract ERC1271Wallet is IERC1271 {
    address public owner;
    
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH = 
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("ERC1271Wallet");
    bytes32 private constant VERSION_HASH = keccak256("1");

    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @notice Compute the wrapped digest for testing purposes
     * @dev External helper to allow tests to compute what digest to sign
     */
    function getWrappedDigest(bytes32 originalDigest) external view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
        
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, originalDigest));
    }

    /**
     * @dev See {IERC1271-isValidSignature}.
     * This implementation protects against signature replay by wrapping the
     * incoming digest with this wallet's domain separator before verification.
     * 
     * SECURITY: Without this wrapping, if the same EOA owns multiple smart wallets,
     * a signature valid for one wallet could be replayed on another wallet.
     */
    function isValidSignature(bytes32 _hash, bytes memory _signature)
        external
        view
        returns (bytes4)
    {
        // Compute this wallet's domain separator
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
        
        // Wrap the incoming digest with wallet's domain (nested EIP-712)
        bytes32 wrappedDigest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, _hash)
        );
        
        // Verify signature against wrapped digest
        address signer = ECDSA.recover(wrappedDigest, _signature);
        if (signer == owner) {
            return IERC1271.isValidSignature.selector; // Return magic value on success
        } else {
            return bytes4(0); // Return a non-magic value on failure
        }
    }
}