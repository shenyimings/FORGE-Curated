// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

library SignatureDecoder {
  // Decode transaction.signature into signature, validator and hook data
  function decodeSignature(
    bytes calldata txSignature
  ) internal pure returns (bytes memory signature, address validator, bytes memory validatorData) {
    (signature, validator, validatorData) = abi.decode(txSignature, (bytes, address, bytes));
  }

  // Decode signature into signature and validator
  function decodeSignatureNoHookData(
    bytes memory signatureAndValidator
  ) internal pure returns (bytes memory signature, address validator) {
    (signature, validator) = abi.decode(signatureAndValidator, (bytes, address));
  }
}
