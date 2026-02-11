// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IERC7579Module
 * @notice Interface for ERC-7579 modules
 * @dev Base interface that all module types must implement
 */
interface IERC7579Module {
    /**
     * @notice Initialize the module for a smart account
     * @param data Initialization data
     */
    function onInstall(
        bytes calldata data
    ) external;

    /**
     * @notice Deinitialize the module for a smart account
     * @param data Deinitialization data
     */
    function onUninstall(
        bytes calldata data
    ) external;

    /**
     * @notice Check if the module is initialized for a smart account
     * @param smartAccount The smart account to check
     * @return True if the module is initialized for the account
     */
    function isInitialized(
        address smartAccount
    ) external view returns (bool);

    /**
     * @notice Check if this contract implements a specific module type
     * @param moduleTypeId The module type identifier to check
     * @return True if the module is of the specified type
     */
    function isModuleType(
        uint256 moduleTypeId
    ) external view returns (bool);
}
