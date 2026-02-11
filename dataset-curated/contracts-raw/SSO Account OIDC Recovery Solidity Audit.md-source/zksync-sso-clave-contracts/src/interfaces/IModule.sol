// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Module interface
/// @dev Interface for a module that can be added to SSO account (e.g. hook or validator).
interface IModule {
  /// @dev This function is called by the smart account during installation of the module
  /// @param data arbitrary data that may be required on the module during `onInstall` initialization
  function onInstall(bytes calldata data) external;

  /// @dev This function is called by the smart account during uninstallation of the module
  /// @param data arbitrary data that may be required on the module during `onUninstall` de-initialization
  function onUninstall(bytes calldata data) external;
}
