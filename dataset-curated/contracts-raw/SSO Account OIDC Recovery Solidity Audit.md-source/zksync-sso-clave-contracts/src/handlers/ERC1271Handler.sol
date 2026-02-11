// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { IERC1271Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { SignatureDecoder } from "../libraries/SignatureDecoder.sol";
import { IModuleValidator } from "../interfaces/IModuleValidator.sol";
import { OwnerManager } from "../managers/OwnerManager.sol";
import { ValidatorManager } from "../managers/ValidatorManager.sol";

/// @title ERC1271Handler
/// @author Matter Labs
/// @notice Contract which provides ERC1271 signature validation
/// @notice The implementation is inspired by Clave wallet.
abstract contract ERC1271Handler is IERC1271Upgradeable, OwnerManager, ValidatorManager {
  bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;

  /**
   * @dev Should return whether the signature provided is valid for the provided data. Does not run validation hooks.
   * @param hash bytes32 - Hash of the data that is signed
   * @param signature bytes calldata - K1 owner signature OR validator address concatenated to signature
   * @return magicValue bytes4 - Magic value if the signature is valid, 0 otherwise
   */
  function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4 magicValue) {
    if (signature.length == 65) {
      (address signer, ECDSA.RecoverError err) = ECDSA.tryRecover(hash, signature);
      return
        signer == address(0) || err != ECDSA.RecoverError.NoError || !_isK1Owner(signer) ? bytes4(0) : _ERC1271_MAGIC;
    }

    (bytes memory decodedSignature, address validator) = SignatureDecoder.decodeSignatureNoHookData(signature);

    bool isValid = _isModuleValidator(validator) &&
      IModuleValidator(validator).validateSignature(hash, decodedSignature);

    magicValue = isValid ? _ERC1271_MAGIC : bytes4(0);
  }
}
