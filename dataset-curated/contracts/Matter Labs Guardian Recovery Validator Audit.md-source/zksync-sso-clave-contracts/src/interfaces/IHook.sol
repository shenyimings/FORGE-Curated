// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IModule } from "./IModule.sol";

/// @title Validation hook interface for native AA
/// @author Initially getclave.io, updated by Matter Labs
/// @notice Validation hooks trigger before each transaction,
/// can be used to enforce additional restrictions on the account and/or transaction during the validation phase.
interface IValidationHook is IModule, IERC165 {
  /// @notice Hook that triggers before each transaction during the validation phase.
  /// @param signedHash Hash of the transaction that is being validated.
  /// @param transaction Transaction that is being validated.
  /// @dev If reverts, the transaction is rejected from the mempool and not included in the block.
  function validationHook(bytes32 signedHash, Transaction calldata transaction) external;
}

/// @title Execution hook interface for native AA
/// @author Initially getclave.io, updated by Matter Labs
/// @notice Execution hooks trigger before and after each transaction, during the execution phase.
interface IExecutionHook is IModule, IERC165 {
  /// @notice Hook that triggers before each transaction during the execution phase.
  /// @param transaction Transaction that is being executed.
  /// @return context Context that is passed to the postExecutionHook.
  function preExecutionHook(Transaction calldata transaction) external returns (bytes memory context);

  /// @notice Hook that triggers after each transaction during the execution phase.
  /// @param context Context that was returned by the preExecutionHook.
  function postExecutionHook(bytes calldata context) external;
}
