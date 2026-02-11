// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ExcessivelySafeCall } from "@nomad-xyz/excessively-safe-call/src/ExcessivelySafeCall.sol";

import { Auth } from "../auth/Auth.sol";
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
abstract contract ValidatorManager is IValidatorManager, Auth {
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
    validator.excessivelySafeCall(gasleft(), 0, abi.encodeWithSelector(IModule.onUninstall.selector, deinitData));
  }

  /// @inheritdoc IValidatorManager
  function isModuleValidator(address validator) external view override returns (bool) {
    return _isModuleValidator(validator);
  }

  /// @inheritdoc IValidatorManager
  function listModuleValidators() external view override returns (address[] memory validatorList) {
    validatorList = _moduleValidators().values();
  }

  function _addModuleValidator(address validator, bytes memory initData) internal {
    if (!_supportsModuleValidator(validator)) {
      revert Errors.VALIDATOR_ERC165_FAIL(validator);
    }

    _moduleValidators().add(validator);
    IModule(validator).onInstall(initData);

    emit ValidatorAdded(validator);
  }

  function _removeModuleValidator(address validator) internal {
    _moduleValidators().remove(validator);

    emit ValidatorRemoved(validator);
  }

  function _isModuleValidator(address validator) internal view returns (bool) {
    return _moduleValidators().contains(validator);
  }

  function _supportsModuleValidator(address validator) private view returns (bool) {
    return
      validator.supportsInterface(type(IModuleValidator).interfaceId) &&
      validator.supportsInterface(type(IModule).interfaceId);
  }

  function _moduleValidators() private view returns (EnumerableSet.AddressSet storage moduleValidators) {
    moduleValidators = SsoStorage.layout().moduleValidators;
  }
}
