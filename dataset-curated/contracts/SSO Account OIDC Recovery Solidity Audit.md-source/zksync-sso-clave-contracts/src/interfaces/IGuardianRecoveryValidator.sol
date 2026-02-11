// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IModuleValidator } from "./IModuleValidator.sol";
import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";

interface IGuardianRecoveryValidator is IModuleValidator {
  function proposeValidationKey(bytes32 hashedOriginDomain, address externalAccount) external;

  function removeValidationKey(bytes32 hashedOriginDomain, address externalAccount) external;

  function initRecovery(
    address accountToRecover,
    bytes32 hashedCredentialId,
    bytes32[2] memory rawPublicKey,
    bytes32 hashedOriginDomain
  ) external;

  function addValidationKey(bytes32 hashedOriginDomain, address accountToGuard) external returns (bool);

  function validateTransaction(bytes32 signedHash, Transaction calldata transaction) external returns (bool);

  function validateSignature(bytes32 signedHash, bytes memory signature) external view returns (bool);
}
