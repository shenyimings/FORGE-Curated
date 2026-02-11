// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IExecutor
 * @notice Interface for ERC-7579 executor modules
 * @dev Executor modules can execute custom logic on behalf of the smart account
 */
interface IExecutor {
    /**
     * @notice Execute custom logic
     * @param account The smart account that is executing
     * @param data Execution data specific to the module's logic
     * @return result The result of the execution
     */
    function execute(address account, bytes calldata data) external returns (bytes memory result);
}
