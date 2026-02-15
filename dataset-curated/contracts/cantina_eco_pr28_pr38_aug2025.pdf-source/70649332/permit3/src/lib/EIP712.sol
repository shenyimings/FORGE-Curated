// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/EIP712.sol)

pragma solidity ^0.8.20;

import { IERC5267 } from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import { ShortString, ShortStrings } from "@openzeppelin/contracts/utils/ShortStrings.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @dev https://eips.ethereum.org/EIPS/eip-712[EIP-712] is a standard for hashing and signing of typed structured data.
 *
 * @custom:oz-upgrades-unsafe-allow state-variable-immutable
 */
abstract contract EIP712 is IERC5267 {
    using ShortStrings for *;

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev Chain ID used for cross-chain compatibility in Permit3
    /// @dev Value of 1 enables signatures to work across all chains
    uint256 private constant CROSS_CHAIN_ID = 1;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _cachedDomainSeparator;
    uint256 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    ShortString private immutable _name;
    ShortString private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    /**
     * @dev Initializes the domain separator and parameter caches.
     *
     * The meaning of `name` and `version` is specified in
     * https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator[EIP-712]:
     *
     * - `name`: the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     * - `version`: the current major version of the signing domain.
     *
     * NOTE: These parameters cannot be changed except through a xref:learn::upgrading-smart-contracts.adoc[smart
     * contract upgrade].
     */
    constructor(string memory name, string memory version) {
        _name = name.toShortStringWithFallback(_nameFallback);
        _version = version.toShortStringWithFallback(_versionFallback);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        _cachedChainId = CROSS_CHAIN_ID;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    /**
     * @dev Returns the domain separator for the current chain
     * @return The EIP-712 domain separator hash
     * @notice This function returns the cached domain separator if the contract
     *         address hasn't changed (no proxy implementation changes).
     *         Otherwise, it rebuilds the domain separator to ensure correctness.
     * @notice The domain separator is used in EIP-712 typed data signing to prevent
     *         signature replay attacks across different domains.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    /**
     * @dev Builds the EIP-712 domain separator from current contract state
     * @return The freshly computed domain separator hash
     * @notice Computes keccak256 of the encoded domain struct containing:
     *         - TYPE_HASH: The EIP-712 domain type hash
     *         - _hashedName: The hashed name of the signing domain
     *         - _hashedVersion: The hashed version of the signing domain
     *         - CROSS_CHAIN_ID: Constant chain ID (1) for cross-chain compatibility
     *         - address(this): The verifying contract address
     * @notice This uses CROSS_CHAIN_ID=1 instead of block.chainid to enable
     *         cross-chain signature compatibility in the Permit3 system
     */
    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, CROSS_CHAIN_ID, address(this)));
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    /**
     * @dev See {IERC-5267}.
     */
    function eip712Domain()
        public
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        /// @dev Fields byte encodes what fields are present in the domain separator
        /// @dev 0x0f = 0b01111 indicates: name (bit 0), version (bit 1), chainId (bit 2), verifyingContract (bit 3)
        bytes1 EIP712_FIELDS = hex"0f";

        return (
            EIP712_FIELDS, _EIP712Name(), _EIP712Version(), CROSS_CHAIN_ID, address(this), bytes32(0), new uint256[](0)
        );
    }

    /**
     * @dev Returns the name parameter for the EIP712 domain
     * @return The name string used in the EIP-712 domain separator
     * @notice This function efficiently retrieves the domain name by:
     *         1. First attempting to read from the immutable ShortString _name
     *         2. Falling back to storage _nameFallback if the name is too long
     * @notice ShortStrings optimization stores strings up to 31 bytes inline,
     *         avoiding storage reads for most use cases
     */
    // solhint-disable-next-line func-name-mixedcase
    function _EIP712Name() internal view returns (string memory) {
        return _name.toStringWithFallback(_nameFallback);
    }

    /**
     * @dev Returns the version parameter for the EIP712 domain
     * @return The version string used in the EIP-712 domain separator
     * @notice This function efficiently retrieves the domain version by:
     *         1. First attempting to read from the immutable ShortString _version
     *         2. Falling back to storage _versionFallback if the version is too long
     * @notice ShortStrings optimization stores strings up to 31 bytes inline,
     *         avoiding storage reads for most use cases
     */
    // solhint-disable-next-line func-name-mixedcase
    function _EIP712Version() internal view returns (string memory) {
        return _version.toStringWithFallback(_versionFallback);
    }
}
