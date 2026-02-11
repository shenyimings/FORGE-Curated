// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IExecutor} from "./interfaces/IExecutor.sol";

import {Call} from "./types/Intent.sol";

/**
 * @title Executor
 * @notice Contract for secure batch execution of intent calls
 * @dev Implements IExecutor with comprehensive safety checks and authorization controls
 * - Only the portal contract can execute calls (onlyPortal modifier)
 * - Prevents malicious calls through EOA validation
 * - Supports batch execution for multiple calls in a single transaction
 */
contract Executor is IExecutor {
    /**
     * @notice Address of the portal contract authorized to call execute
     */
    address private immutable portal;

    /**
     * @notice Initializes the Executor contract
     * @dev Sets the deploying address (portal) as the only authorized caller
     */
    constructor() {
        portal = msg.sender;
    }

    /**
     * @notice Restricts function access to the portal contract only
     * @dev Reverts with NonPortalCaller error if caller is not the portal
     */
    modifier onlyPortal() {
        if (msg.sender != portal) {
            revert NonPortalCaller(msg.sender);
        }

        _;
    }

    /**
     * @notice Executes multiple intent calls with comprehensive safety checks
     * @dev Performs validation and execution for each call in the batch:
     * 1. Prevents calls to EOAs that include calldata (potential phishing protection)
     * 2. Executes each call and returns results or reverts on any failure
     * @param calls Array of call data containing target addresses, values, and calldata
     * @return Array of return data from the successfully executed calls
     */
    function execute(
        Call[] calldata calls
    ) external payable override onlyPortal returns (bytes[] memory) {
        uint256 callsLength = calls.length;
        bytes[] memory results = new bytes[](callsLength);

        for (uint256 i = 0; i < callsLength; i++) {
            results[i] = execute(calls[i]);
        }

        return results;
    }

    function execute(Call calldata call) internal returns (bytes memory) {
        if (_isCallToEoa(call)) {
            revert CallToEOA(call.target);
        }

        (bool success, bytes memory result) = call.target.call{
            value: call.value
        }(call.data);

        if (!success) {
            revert CallFailed(call, result);
        }

        return result;
    }

    /**
     * @notice Checks if a call is targeting an EOA with calldata
     * @dev Returns true if target has no code but calldata is provided
     * This prevents potential phishing attacks where calldata might be misinterpreted
     * @param call The call to validate
     * @return bool True if this is a potentially unsafe call to an EOA
     */
    function _isCallToEoa(Call calldata call) internal view returns (bool) {
        return call.target.code.length == 0 && call.data.length > 0;
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev Required for handling ETH transfer for intent execution
     */
    receive() external payable {}
}
