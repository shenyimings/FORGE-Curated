// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { ExcessivelySafeCall } from "@nomad-xyz/excessively-safe-call/src/ExcessivelySafeCall.sol";

import { SelfAuth } from "../auth/SelfAuth.sol";
import { SsoStorage } from "../libraries/SsoStorage.sol";
import { Errors } from "../libraries/Errors.sol";
import { IExecutionHook, IValidationHook } from "../interfaces/IHook.sol";
import { IHookManager } from "../interfaces/IHookManager.sol";
import { IModule } from "../interfaces/IModule.sol";

/**
 * @title Manager contract for hooks
 * @notice Abstract contract for managing the enabled hooks of the account
 * @dev Hook addresses are stored in an enumerable set
 * @author Initially https://getclave.io, then updated by Matter Labs
 */
abstract contract HookManager is IHookManager, SelfAuth {
  using EnumerableSet for EnumerableSet.AddressSet;
  // Interface helper library
  using ERC165Checker for address;
  // Low level calls helper library
  using ExcessivelySafeCall for address;

  /// @inheritdoc IHookManager
  function addHook(address hook, bool isValidation, bytes calldata initData) external override onlySelf {
    _addHook(hook, isValidation, initData);
  }

  /// @inheritdoc IHookManager
  function removeHook(address hook, bool isValidation, bytes calldata deinitData) external override onlySelf {
    _removeHook(hook, isValidation);
    IModule(hook).onUninstall(deinitData);
  }

  /// @inheritdoc IHookManager
  function unlinkHook(address hook, bool isValidation, bytes calldata deinitData) external onlySelf {
    _removeHook(hook, isValidation);
    // Allow-listing slither finding as we don´t want reverting calls to prevent unlinking
    // slither-disable-next-line unused-return
    hook.excessivelySafeCall(gasleft(), 0, abi.encodeCall(IModule.onUninstall, (deinitData)));
  }

  /// @inheritdoc IHookManager
  function isHook(address addr) external view override returns (bool) {
    return _isHook(addr);
  }

  /// @inheritdoc IHookManager
  function listHooks(bool isValidation) external view override returns (address[] memory hookList) {
    if (isValidation) {
      hookList = SsoStorage.validationHooks().values();
    } else {
      hookList = SsoStorage.executionHooks().values();
    }
  }

  // Runs the validation hooks that are enabled by the account and returns true if none reverts
  function runValidationHooks(bytes32 signedHash, Transaction calldata transaction) internal returns (bool) {
    EnumerableSet.AddressSet storage hookList = SsoStorage.validationHooks();
    uint256 totalHooks = hookList.length();

    for (uint256 i = 0; i < totalHooks; i++) {
      bool success = _call(hookList.at(i), abi.encodeCall(IValidationHook.validationHook, (signedHash, transaction)));

      if (!success) {
        return false;
      }
    }

    return true;
  }

  // Runs the execution hooks that are enabled by the account before and after _executeTransaction
  modifier runExecutionHooks(Transaction calldata transaction) {
    address[] memory hookList = SsoStorage.executionHooks().values();
    uint256 totalHooks = hookList.length;
    bytes[] memory context = new bytes[](totalHooks);

    for (uint256 i = 0; i < totalHooks; i++) {
      context[i] = IExecutionHook(hookList[i]).preExecutionHook(transaction);
    }

    _;

    EnumerableSet.AddressSet storage newHookList = SsoStorage.executionHooks();

    for (uint256 i = 0; i < totalHooks; i++) {
      // Only execute hooks which are both in the old `hookList` and the `newHookList`,
      // and we don't want to execute hooks that were removed and/or added during this transaction.
      if (newHookList.contains(hookList[i])) {
        IExecutionHook(hookList[i]).postExecutionHook(context[i]);
      }
    }
  }

  function _addHook(address hook, bool isValidation, bytes calldata initData) private {
    if (!_supportsHook(hook, isValidation)) {
      revert Errors.HOOK_ERC165_FAIL(hook, isValidation);
    }

    // Regardless of whether or not it is a validation or an execution hook,
    // if the module is already installed, it cannot be installed again (even as another type).
    if (SsoStorage.validationHooks().contains(hook)) {
      revert Errors.HOOK_ALREADY_EXISTS(hook, true);
    }
    if (SsoStorage.executionHooks().contains(hook)) {
      revert Errors.HOOK_ALREADY_EXISTS(hook, false);
    }
    if (SsoStorage.validators().contains(hook)) {
      revert Errors.VALIDATOR_ALREADY_EXISTS(hook);
    }

    // No need to check the return value of .add() as we just checked that it is not already present.
    if (isValidation) {
      bool _result = SsoStorage.validationHooks().add(hook);
    } else {
      bool _result = SsoStorage.executionHooks().add(hook);
    }

    IModule(hook).onInstall(initData);

    emit HookAdded(hook);
  }

  function _removeHook(address hook, bool isValidation) private {
    if (isValidation) {
      if (!SsoStorage.validationHooks().remove(hook)) {
        revert Errors.HOOK_NOT_FOUND(hook, isValidation);
      }
    } else {
      if (!SsoStorage.executionHooks().remove(hook)) {
        revert Errors.HOOK_NOT_FOUND(hook, isValidation);
      }
    }

    emit HookRemoved(hook);
  }

  function _isHook(address addr) internal view returns (bool) {
    return SsoStorage.validationHooks().contains(addr) || SsoStorage.executionHooks().contains(addr);
  }

  function _call(address target, bytes memory data) private returns (bool success) {
    assembly ("memory-safe") {
      success := call(gas(), target, 0, add(data, 0x20), mload(data), 0, 0)
    }
  }

  function _supportsHook(address hook, bool isValidation) private view returns (bool) {
    return
      hook.supportsInterface(type(IModule).interfaceId) &&
      (
        isValidation
          ? hook.supportsInterface(type(IValidationHook).interfaceId)
          : hook.supportsInterface(type(IExecutionHook).interfaceId)
      );
  }
}
