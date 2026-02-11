/*
 * SPDX-License-Identifier:    MIT
 */

pragma solidity ^0.6.2;


interface IEVMScriptExecutor {
    function execScript(bytes calldata script, bytes calldata input, address[] calldata blacklist) external returns (bytes memory);
    function executorType() external pure returns (bytes32);
}