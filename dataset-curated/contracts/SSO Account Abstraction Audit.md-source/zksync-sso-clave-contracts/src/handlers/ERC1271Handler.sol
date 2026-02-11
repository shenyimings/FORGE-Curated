// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { IERC1271Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { SignatureDecoder } from "../libraries/SignatureDecoder.sol";
import { IModuleValidator } from "../interfaces/IModuleValidator.sol";
import { OwnerManager } from "../managers/OwnerManager.sol";
import { ValidatorManager } from "../managers/ValidatorManager.sol";

/// @title ERC1271Handler
/// @author Matter Labs
/// @notice Contract which provides ERC1271 signature validation
/// @notice The implementation is inspired by Clave wallet.
abstract contract ERC1271Handler is IERC1271Upgradeable, EIP712("Sso1271", "1.0.0"), OwnerManager, ValidatorManager {
  struct SsoMessage {
    bytes32 signedHash;
  }

  bytes32 private constant _SSO_MESSAGE_TYPEHASH = keccak256("SsoMessage(bytes32 signedHash)");

  bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;

  /**
   * @dev Should return whether the signature provided is valid for the provided data. Does not run validation hooks.
   * @param hash bytes32 - Hash of the data that is signed
   * @param signature bytes calldata - K1 owner signature OR validator address concatenated to signature
   * @return magicValue bytes4 - Magic value if the signature is valid, 0 otherwise
   */
  function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4 magicValue) {
    if (signature.length == 65) {
      (address signer, ECDSA.RecoverError error) = ECDSA.tryRecover(hash, signature);
      return
        signer == address(0) || error != ECDSA.RecoverError.NoError || !_k1IsOwner(signer) ? bytes4(0) : _ERC1271_MAGIC;
    }

    (bytes memory decodedSignature, address validator) = SignatureDecoder.decodeSignatureNoHookData(signature);

    bytes32 eip712Hash = _hashTypedDataV4(_ssoMessageHash(SsoMessage(hash)));

    bool isValid = _isModuleValidator(validator) &&
      IModuleValidator(validator).validateSignature(eip712Hash, decodedSignature);

    magicValue = isValid ? _ERC1271_MAGIC : bytes4(0);
  }

  /**
   * @notice Returns the EIP-712 hash of the Sso message
   * @param ssoMessage SsoMessage calldata - The message containing signedHash
   * @return bytes32 - EIP712 hash of the message
   */
  function getEip712Hash(SsoMessage calldata ssoMessage) external view returns (bytes32) {
    return _hashTypedDataV4(_ssoMessageHash(ssoMessage));
  }

  /**
   * @notice Returns the typehash for the sso message struct
   * @return bytes32 - Sso message typehash
   */
  function ssoMessageTypeHash() external pure returns (bytes32) {
    return _SSO_MESSAGE_TYPEHASH;
  }

  function _ssoMessageHash(SsoMessage memory ssoMessage) private pure returns (bytes32) {
    return keccak256(abi.encode(_SSO_MESSAGE_TYPEHASH, ssoMessage.signedHash));
  }
}
