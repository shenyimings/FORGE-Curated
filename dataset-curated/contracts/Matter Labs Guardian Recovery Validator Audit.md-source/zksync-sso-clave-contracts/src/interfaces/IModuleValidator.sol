// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { IModule } from "./IModule.sol";

/**
 * @title Modular validator interface for native AA
 * @notice Validators are used for custom validation of transactions and/or message signatures
 */
interface IModuleValidator is IModule, IERC165 {
  /**
   * @notice Validate transaction for account
   * @param signedHash Hash of the transaction
   * @param transaction Transaction to validate
   * @return bool True if transaction is valid
   */
  function validateTransaction(bytes32 signedHash, Transaction calldata transaction) external returns (bool);

  /**
   * @notice Validate signature for account (including via EIP-1271)
   * @dev If module is not supposed to validate signatures, it MUST return false
   * @param signedHash Hash of the message
   * @param signature Signature of the message
   * @return bool True if signature is valid
   */
  function validateSignature(bytes32 signedHash, bytes calldata signature) external view returns (bool);
}
