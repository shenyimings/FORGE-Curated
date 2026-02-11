// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ExcessivelySafeCall } from "@nomad-xyz/excessively-safe-call/src/ExcessivelySafeCall.sol";

import { SelfAuth } from "../auth/SelfAuth.sol";
import { Errors } from "../libraries/Errors.sol";
import { SsoStorage } from "../libraries/SsoStorage.sol";
import { IValidatorManager } from "../interfaces/IValidatorManager.sol";
import { IModuleValidator } from "../interfaces/IModuleValidator.sol";
import { IModule } from "../interfaces/IModule.sol";

/**
 * @title Manager contract for validators
 * @notice Abstract contract for managing the validators of the account
 * @dev Validators are stored in an enumerable set
 * @author https://getclave.io
 */
abstract contract ValidatorManager is IValidatorManager, SelfAuth {
  using EnumerableSet for EnumerableSet.AddressSet;
  // Interface helper library
  using ERC165Checker for address;
  // Low level calls helper library
  using ExcessivelySafeCall for address;

  ///@inheritdoc IValidatorManager
  function addModuleValidator(address validator, bytes calldata initData) external onlySelf {
    _addModuleValidator(validator, initData);
  }

  ///@inheritdoc IValidatorManager
  function removeModuleValidator(address validator, bytes calldata deinitData) external onlySelf {
    _removeModuleValidator(validator);
    IModule(validator).onUninstall(deinitData);
  }

  ///@inheritdoc IValidatorManager
  function unlinkModuleValidator(address validator, bytes calldata deinitData) external onlySelf {
    _removeModuleValidator(validator);
    // Allow-listing slither finding as we don´t want reverting calls to prevent unlinking
    // slither-disable-next-line unused-return
    validator.excessivelySafeCall(gasleft(), 0, abi.encodeCall(IModule.onUninstall, (deinitData)));
  }

  /// @inheritdoc IValidatorManager
  function isModuleValidator(address validator) external view override returns (bool) {
    return _isModuleValidator(validator);
  }

  /// @inheritdoc IValidatorManager
  function listModuleValidators() external view override returns (address[] memory validatorList) {
    validatorList = SsoStorage.validators().values();
  }

  // Should not be set to private as it is called from SsoAccount's initialize
  function _addModuleValidator(address validator, bytes memory initData) internal {
    if (!_supportsModuleValidator(validator)) {
      revert Errors.VALIDATOR_ERC165_FAIL(validator);
    }

    // If the module is already installed, it cannot be installed again (even as another type).
    if (SsoStorage.validationHooks().contains(validator)) {
      revert Errors.HOOK_ALREADY_EXISTS(validator, true);
    }
    if (SsoStorage.executionHooks().contains(validator)) {
      revert Errors.HOOK_ALREADY_EXISTS(validator, false);
    }
    if (!SsoStorage.validators().add(validator)) {
      revert Errors.VALIDATOR_ALREADY_EXISTS(validator);
    }

    IModule(validator).onInstall(initData);

    emit ValidatorAdded(validator);
  }

  function _removeModuleValidator(address validator) private {
    if (!SsoStorage.validators().remove(validator)) {
      revert Errors.VALIDATOR_NOT_FOUND(validator);
    }

    emit ValidatorRemoved(validator);
  }

  function _isModuleValidator(address validator) internal view returns (bool) {
    return SsoStorage.validators().contains(validator);
  }

  function _supportsModuleValidator(address validator) private view returns (bool) {
    return
      validator.supportsInterface(type(IModuleValidator).interfaceId) &&
      validator.supportsInterface(type(IModule).interfaceId);
  }
}
