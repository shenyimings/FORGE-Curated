 // SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Universal Router Interface
/// @notice Interface for the Uniswap Universal Router contract
interface IUniversalRouter {
    /// @notice Executes a series of commands on the Universal Router.
    /// @param commands The commands to execute.
    /// @param inputs The inputs to the commands.
    /// @param deadline The deadline for the execution.
    function execute(
        bytes calldata commands, 
        bytes[] calldata inputs, 
        uint256 deadline
    ) external payable;
}