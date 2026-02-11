// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Call} from "../types/Intent.sol";

/**
 * @title IExecutor
 * @notice Interface for secure batch execution of intent calls
 * @dev Provides controlled execution with built-in safety checks and authorization
 * - Restricts execution to authorized portal contracts only
 * - Prevents calls to EOAs with calldata
 * - Supports batch execution for multiple calls in a single transaction
 */
interface IExecutor {
    /**
     * @notice Thrown when caller is not the portal to execute calls
     * @param caller The unauthorized address that attempted the call
     */
    error NonPortalCaller(address caller);

    /**
     * @notice Attempted call to an EOA
     * @param target EOA address to which call was attempted
     */
    error CallToEOA(address target);

    /**
     * @notice Call to a contract failed
     * @param call The call that failed
     * @param reason The reason for the failure
     */
    error CallFailed(Call call, bytes reason);

    /**
     * @notice Executes multiple intent calls with safety checks
     * @dev Validates each target address and executes calls if safe
     * - Prevents calls to EOAs that include calldata
     * - Reverts if any target call fails
     * @param calls Array of call data containing target, value, and calldata
     * @return Array of return data from the executed calls
     */
    function execute(
        Call[] calldata calls
    ) external payable returns (bytes[] memory);
}
