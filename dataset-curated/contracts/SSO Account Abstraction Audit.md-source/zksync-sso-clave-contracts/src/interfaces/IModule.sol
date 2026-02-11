/**
 * @title Module interface
 * @dev Interface for a module that can be added to SSO account (e.g. hook or validator).
 */
interface IModule {
  /**
   * @dev This function is called by the smart account during installation of the module
   * @param data arbitrary data that may be required on the module during `onInstall` initialization
   *
   * MUST revert on error (e.g. if module is already enabled)
   */
  function onInstall(bytes calldata data) external;

  /**
   * @dev This function is called by the smart account during uninstallation of the module
   * @param data arbitrary data that may be required on the module during `onUninstall` de-initialization
   *
   * MUST revert on error
   */
  function onUninstall(bytes calldata data) external;
}
