// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";

/**
 * @title PasskeyWallet
 * @notice Mock wallet that simulates passkey/WebAuthn signature validation with replay protection
 * @dev For testing purposes: accepts any signature that starts with a specific prefix
 * This simulates a wallet that validates non-ECDSA signatures (like Ed25519, WebAuthn, etc.)
 * 
 * SECURITY: Wraps incoming digest with wallet's domain separator to prevent signature 
 * replay attacks across multiple wallets owned by the same user.
 * See: https://www.alchemy.com/blog/erc-1271-signature-replay-vulnerability
 */
contract PasskeyWallet is IERC1271 {
    bytes32 public constant MAGIC_PREFIX = keccak256("PASSKEY_SIG");
    address public owner;
    
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH = 
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("PasskeyWallet");
    bytes32 private constant VERSION_HASH = keccak256("1");
    
    // Track which WRAPPED digests this wallet has "approved"
    // Note: We store wrapped digests to simulate the user approving the actual message
    mapping(bytes32 => bool) public approvedDigests;

    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @notice Pre-approve a digest for testing (simulates passkey confirmation)
     * @dev In a real passkey wallet, the user would confirm via biometrics/PIN
     * @param unwrappedDigest The original digest from the application (e.g., Tea token)
     */
    function approveDigest(bytes32 unwrappedDigest) external {
        require(msg.sender == owner, "Only owner can approve");
        
        // Wrap the digest with wallet's domain separator
        bytes32 wrappedDigest = _wrapDigest(unwrappedDigest);
        approvedDigests[wrappedDigest] = true;
    }

    /**
     * @dev Compute wrapped digest using this wallet's domain separator
     */
    function _wrapDigest(bytes32 digest) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
        
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, digest));
    }

    /**
     * @dev See {IERC1271-isValidSignature}.
     * This implementation accepts any signature with the MAGIC_PREFIX for approved digests
     * Simulates a passkey wallet validating WebAuthn/Ed25519 signatures
     * 
     * SECURITY: Wraps incoming digest before validation to prevent replay attacks
     */
    function isValidSignature(bytes32 _hash, bytes memory _signature)
        external
        view
        returns (bytes4)
    {
        // Wrap the incoming digest with wallet's domain separator
        bytes32 wrappedDigest = _wrapDigest(_hash);
        
        // Check if wrapped digest is approved
        if (!approvedDigests[wrappedDigest]) {
            return bytes4(0);
        }
        
        // Check signature format (must start with MAGIC_PREFIX)
        if (_signature.length < 32) {
            return bytes4(0);
        }
        
        bytes32 prefix;
        assembly {
            prefix := mload(add(_signature, 32))
        }
        
        if (prefix == MAGIC_PREFIX) {
            return IERC1271.isValidSignature.selector;
        }
        
        return bytes4(0);
    }
}
