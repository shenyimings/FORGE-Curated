// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @notice Builds off of "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol" by copying its code to make
 * the nonces more useful for signatures, namely:
 * - tracking nonces per account per operation rather than just per account
 * - allowing public nonce use by the account in question (e.g. for cancellation)
 *
 * @custom:security-contact security@af.xyz
 */
abstract contract SignatureNoncesUpgradeable is Initializable {
    /// @dev The nonce used for an `account` and `signatureType` is not the expected current nonce.
    error InvalidNonce(address account, bytes32 signatureType, uint256 currentNonce);

    /// @custom:storage-location erc7201:anvil.storage.SignatureNonces
    struct SignatureNoncesStorage {
        /// Stores nonces for the specified account and signature type.
        mapping(address account => mapping(bytes32 signatureType => uint256 nonce)) _accountTypeNonces;
    }

    // keccak256(abi.encode(uint256(keccak256("anvil.storage.SignatureNonces")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SignatureNoncesStorageLocation =
        0xa10463db4f5369b35ba0ad7c2c4710776052e62babfb578b03cd47bf9aa4f100;

    function _getSignatureNoncesStorage() private pure returns (SignatureNoncesStorage storage $) {
        assembly {
            $.slot := SignatureNoncesStorageLocation
        }
    }

    function __Nonces_init() internal onlyInitializing {}

    function __Nonces_init_unchained() internal onlyInitializing {}

    /**
     * @dev Returns the next unused nonce for an address and signature type.
     */
    function nonces(address _owner, bytes32 _signatureType) public view virtual returns (uint256) {
        SignatureNoncesStorage storage $ = _getSignatureNoncesStorage();
        return $._accountTypeNonces[_owner][_signatureType];
    }

    /**
     * @dev Consumes a nonce.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address _owner, bytes32 _signatureType) internal virtual returns (uint256) {
        SignatureNoncesStorage storage $ = _getSignatureNoncesStorage();
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            return $._accountTypeNonces[_owner][_signatureType]++;
        }
    }

    /**
     * @dev Same as {_useNonce} but checking that `nonce` is the next valid for `owner`.
     */
    function _useCheckedNonce(address _owner, bytes32 _signatureType, uint256 _nonce) internal virtual {
        uint256 current = _useNonce(_owner, _signatureType);
        if (_nonce != current) {
            revert InvalidNonce(_owner, _signatureType, current);
        }
    }
}
