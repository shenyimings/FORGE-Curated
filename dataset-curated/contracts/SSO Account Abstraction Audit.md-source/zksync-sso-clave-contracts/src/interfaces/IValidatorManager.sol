// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title Manager contract for validators
 * @author https://getclave.io
 */
interface IValidatorManager {
  /**
   * @notice Event emitted when a modular validator is added
   * @param validator address - Address of the added modular validator
   */
  event ValidatorAdded(address indexed validator);

  /**
   * @notice Event emitted when a modular validator is removed
   * @param validator address - Address of the removed modular validator
   */
  event ValidatorRemoved(address indexed validator);

  /**
   * @notice Adds a validator to the list of modular validators
   * @dev Can only be called by self
   * @param validator address - Address of the generic validator to add
   * @param initData - Data to pass to the validator's `onInstall` function
   */
  function addModuleValidator(address validator, bytes memory initData) external;

  /**
   * @notice Removes a validator from the list of modular validators
   * @dev Can only be called by self
   * @param validator address - Address of the validator to remove
   * @param deinitData - Data to pass to the validator's `onUninstall` function
   */
  function removeModuleValidator(address validator, bytes calldata deinitData) external;

  /**
   * @notice Removes a validator from the list of modular validators while ignoring reverts from its `onUninstall` teardown function.
   * @dev Can only be called by self
   * @param validator address - Address of the validator to remove
   * @param deinitData - Data to pass to the validator's `onUninstall` function
   */
  function unlinkModuleValidator(address validator, bytes calldata deinitData) external;

  /**
   * @notice Checks if an address is in the modular validator list
   * @param validator address - Address of the validator to check
   * @return True if the address is a validator, false otherwise
   */
  function isModuleValidator(address validator) external view returns (bool);

  /**
   * @notice Returns the list of modular validators
   * @return validatorList address[] memory - Array of modular validator addresses
   */
  function listModuleValidators() external view returns (address[] memory validatorList);
}
