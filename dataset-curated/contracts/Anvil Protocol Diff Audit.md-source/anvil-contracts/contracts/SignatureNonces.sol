// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

/**
 * @notice Builds off of "@openzeppelin/contracts/utils/Nonces.sol" by copying its code to make the nonces more useful
 * for signatures, namely:
 * - tracking nonces per account per operation rather than just per account
 * - allowing public nonce use by the account in question (e.g. for cancellation)
 *
 * @custom:security-contact security@af.xyz
 */
abstract contract SignatureNonces {
    /// @dev The nonce used for an `account` and `signatureType` is not the expected current nonce.
    error InvalidNonce(address account, bytes32 signatureType, uint256 currentNonce);

    /// @dev More than `maxNoncesUsedAtOneTime()` nonces are being used at once.
    error SimultaneousUseLimitExceeded(uint256 amountRequested, uint256 max);

    /// account address => signature type (e.g. a hash) => nonce
    mapping(address => mapping(bytes32 => uint256)) private _accountTypeNonces;

    /**
     * @dev Returns the next unused nonce for an address and signature type.
     */
    function nonces(address _owner, bytes32 _signatureType) public view virtual returns (uint256) {
        return _accountTypeNonces[_owner][_signatureType];
    }

    /**
     * @dev The maximum number of nonces that can be used at one time in `_useNoncesUpToAndIncluding`.
     *
     * NOTE: This may be overridden, but the definition of a nonce is that it will not be reused. Setting this to a
     * larger number increases the risk of overflow and reuse.
     * See: `unchecked` blocks in `_useNonce` and `_useNoncesUpToAndIncluding`.
     * @return The maximum number of nonces that may be used at one time.
     */
    function maxNoncesUsedAtOneTime() public view virtual returns (uint256) {
        // This is large enough to allow many to be used at once and supports over 1e74 uses of the max before overflow.
        return 1_000;
    }

    /**
     * @dev Uses all nonces up to and including the provided nonce for the (sender, signature type) pair. A simple use
     * case for this function is to cancel a signature, nullifying the nonce that has been included in it. This function
     * also allows multiple nonces to be used/canceled at once or to cancel a future nonce if many have been exposed.
     *
     * Note: the amount of nonces used is capped by `maxNoncesUsedAtOneTime` and should be tiny compared to `type(uint256).max`.
     * @param _signatureType The signature type for the nonces being used.
     * @param _upToAndIncludingNonce The greatest sequential nonce being used.
     */
    function useNoncesUpToAndIncluding(bytes32 _signatureType, uint256 _upToAndIncludingNonce) public virtual {
        _useNoncesUpToAndIncluding(msg.sender, _signatureType, _upToAndIncludingNonce);
    }

    /**
     * @dev Consumes a nonce for the provided owner and signature type.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address _owner, bytes32 _signatureType) internal virtual returns (uint256) {
        // For each account and signature type, the nonce has an initial value of 0, a relatively small number of nonces
        // may be used at one time, and the nonce cannot be decremented or reset.
        // This makes nonce overflow infeasible.
        unchecked {
            // It is important to do x++ and not ++x here.
            return _accountTypeNonces[_owner][_signatureType]++;
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

    /**
     * @dev Internal function with the same signature as `useNoncesUpToAndIncluding`, assuming authorization has been done.
     */
    function _useNoncesUpToAndIncluding(
        address _owner,
        bytes32 _signatureType,
        uint256 _upToAndIncludingNonce
    ) internal virtual {
        uint256 currentNonce = nonces(_owner, _signatureType);
        if (currentNonce > _upToAndIncludingNonce) revert InvalidNonce(_owner, _signatureType, currentNonce);

        // maxNoncesUsedAtOneTime returning a relatively small number makes underflow and overflow infeasible.
        unchecked {
            uint256 newNonce = _upToAndIncludingNonce + 1;
            if (newNonce - currentNonce > maxNoncesUsedAtOneTime())
                revert SimultaneousUseLimitExceeded(newNonce - currentNonce, maxNoncesUsedAtOneTime());

            _accountTypeNonces[_owner][_signatureType] = newNonce;
        }
    }
}
