// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title Interface of the manager contract for hooks
 * @author https://getclave.io
 */
interface IHookManager {
  /**
   * @notice Event emitted when a hook is added
   * @param hook address - Address of the added hook
   */
  event HookAdded(address indexed hook);

  /**
   * @notice Event emitted when a hook is removed
   * @param hook address - Address of the removed hook
   */
  event HookRemoved(address indexed hook);

  /**
   * @notice Add a hook to the list of hooks and call its init function
   * @dev Can only be called by self
   * @param hook - Address of the hook
   * @param isValidation bool          - True if the hook is a validation hook, false otherwise
   * @param initData bytes calldata    - Data to pass to the hook's `onInstall` function
   */
  function addHook(address hook, bool isValidation, bytes calldata initData) external;

  /**
   * @notice Remove a hook from the list of hooks
   * @dev Can only be called by self
   * @param hook address      - Address of the hook to remove
   * @param isValidation bool - True if the hook is a validation hook, false otherwise
   * @param deinitData bytes calldata - Data to pass to the hook's `onUninstall` function
   */
  function removeHook(address hook, bool isValidation, bytes calldata deinitData) external;

  /**
   * @notice Remove a hook from the list of hooks while ignoring reverts from its `onUninstall` teardown function
   * @dev Can only be called by self
   * @param hook address      - Address of the hook to remove
   * @param isValidation bool - True if the hook is a validation hook, false otherwise
   * @param deinitData bytes calldata - Data to pass to the hook's `onUninstall` function
   */
  function unlinkHook(address hook, bool isValidation, bytes calldata deinitData) external;

  /**
   * @notice Check if an address is in the list of hooks
   * @param addr address - Address to check
   * @return bool        - True if the address is a hook, false otherwise
   */
  function isHook(address addr) external view returns (bool);

  /**
   * @notice Get the list of validation or execution hooks
   * @param isValidation bool          - True if the list of validation hooks should be returned, false otherwise
   * @return hookList address[] memory - List of validation or execution hooks
   */
  function listHooks(bool isValidation) external view returns (address[] memory hookList);
}
