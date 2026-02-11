pragma solidity ^0.8.0;

import {EIP712Upgradeable} from "./EIP712Upgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

abstract contract SignatureModule is EIP712Upgradeable {
    /// @notice Error thrown when a signature is invalid
    error InvalidSignature();

    /// @dev Added supportive function to check if the signature is valid
    function _requireIsValidSignatureNow(address signer, bytes32 structHash, bytes memory signature) internal view {
        if (
            !SignatureChecker.isValidSignatureNow({
                signer: signer,
                hash: _hashTypedDataV4({structHash: structHash}),
                signature: signature
            }) || signer == address(0)
        ) revert InvalidSignature();
    }
}