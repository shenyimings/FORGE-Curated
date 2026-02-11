// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IExecutorModule
 * @notice Interface for ERC-7579 executor modules that return execution arrays
 * @dev Executor modules return execution instructions for the smart account to execute
 */
interface IExecutorModule {
    struct Execution {
        address target;
        uint256 value;
        bytes data;
    }

    /**
     * @notice Generate execution instructions
     * @param account The smart account that will execute
     * @param data Module-specific data
     * @return executions Array of executions for the smart account to perform
     */
    function execute(address account, bytes calldata data) external view returns (Execution[] memory executions);
}
