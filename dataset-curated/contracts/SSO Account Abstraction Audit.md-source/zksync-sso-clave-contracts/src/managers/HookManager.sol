// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { ExcessivelySafeCall } from "@nomad-xyz/excessively-safe-call/src/ExcessivelySafeCall.sol";

import { Auth } from "../auth/Auth.sol";
import { SsoStorage } from "../libraries/SsoStorage.sol";
import { Errors } from "../libraries/Errors.sol";
import { IExecutionHook, IValidationHook } from "../interfaces/IHook.sol";
import { IHookManager } from "../interfaces/IHookManager.sol";
import { IModule } from "../interfaces/IModule.sol";

/**
 * @title Manager contract for hooks
 * @notice Abstract contract for managing the enabled hooks of the account
 * @dev Hook addresses are stored in a linked list
 * @author https://getclave.io
 */
abstract contract HookManager is IHookManager, Auth {
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
    hook.excessivelySafeCall(gasleft(), 0, abi.encodeWithSelector(IModule.onUninstall.selector, deinitData));
  }

  /// @inheritdoc IHookManager
  function isHook(address addr) external view override returns (bool) {
    return _isHook(addr);
  }

  /// @inheritdoc IHookManager
  function listHooks(bool isValidation) external view override returns (address[] memory hookList) {
    if (isValidation) {
      hookList = _validationHooks().values();
    } else {
      hookList = _executionHooks().values();
    }
  }

  // Runs the validation hooks that are enabled by the account and returns true if none reverts
  function runValidationHooks(bytes32 signedHash, Transaction calldata transaction) internal returns (bool) {
    EnumerableSet.AddressSet storage hookList = _validationHooks();
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
    EnumerableSet.AddressSet storage hookList = _executionHooks();
    uint256 totalHooks = hookList.length();

    for (uint256 i = 0; i < totalHooks; i++) {
      IExecutionHook(hookList.at(i)).preExecutionHook(transaction);
    }

    _;

    for (uint256 i = 0; i < totalHooks; i++) {
      IExecutionHook(hookList.at(i)).postExecutionHook();
    }
  }

  function _addHook(address hook, bool isValidation, bytes calldata initData) internal {
    if (!_supportsHook(hook, isValidation)) {
      revert Errors.HOOK_ERC165_FAIL(hook, isValidation);
    }

    if (isValidation) {
      _validationHooks().add(hook);
    } else {
      _executionHooks().add(hook);
    }

    IModule(hook).onInstall(initData);

    emit HookAdded(hook);
  }

  function _removeHook(address hook, bool isValidation) internal {
    if (isValidation) {
      _validationHooks().remove(hook);
    } else {
      _executionHooks().remove(hook);
    }

    emit HookRemoved(hook);
  }

  function _isHook(address addr) internal view override returns (bool) {
    return _validationHooks().contains(addr) || _executionHooks().contains(addr);
  }

  function _call(address target, bytes memory data) private returns (bool success) {
    assembly ("memory-safe") {
      success := call(gas(), target, 0, add(data, 0x20), mload(data), 0, 0)
    }
  }

  function _validationHooks() private view returns (EnumerableSet.AddressSet storage validationHooks) {
    validationHooks = SsoStorage.layout().validationHooks;
  }

  function _executionHooks() private view returns (EnumerableSet.AddressSet storage executionHooks) {
    executionHooks = SsoStorage.layout().executionHooks;
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
