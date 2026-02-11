// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseController } from "./BaseController.sol";

/**
 * @title EmergencyManager
 * @notice Abstract contract that provides emergency functionality for protocol operations
 * @dev Inherits from BaseController and implements pausable functionality with role-based access control
 * The contract allows authorized users with EMERGENCY_MANAGER_ROLE to pause/unpause critical operations
 */
abstract contract EmergencyManager is BaseController {
    /**
     * @notice Role identifier for addresses authorized to pause/unpause the contract
     */
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    /**
     * @notice Emitted when the contract is paused
     */
    event Paused();
    /**
     * @notice Emitted when the contract is unpaused
     */
    event Unpaused();
    /**
     * @notice Emitted when skipping the next rebalance safety buffer check is allowed
     */
    event SkipNextRebalanceSafetyBufferCheckAllowed();

    /**
     * @notice Thrown when attempting to execute a function that requires the contract to be unpaused
     */
    error EmergencyManager_ControllerPaused();
    /**
     * @notice Thrown when attempting to unpause a contract that is not currently paused
     */
    error EmergencyManager_NotPaused();
    /**
     * @notice Thrown when attempting to pause a contract that is already paused
     */
    error EmergencyManager_AlreadyPaused();
    /**
     * @notice Thrown when attempting to allow skipping the next rebalance safety buffer check
     * when it is already allowed
     */
    error EmergencyManager_AlreadyAllowedToSkipNextRebalanceSafetyBufferCheck();

    /**
     * @notice Modifier that restricts function execution to when the contract is not paused
     */
    modifier notPaused() {
        _notPaused();
        _;
    }

    function _notPaused() internal view {
        require(!paused, EmergencyManager_ControllerPaused());
    }

    /**
     * @notice Internal initializer function for the EmergencyManager contract
     * @dev Can only be called during contract initialization
     * Currently empty but reserved for future initialization logic
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __EmergencyManager_init() internal onlyInitializing { }

    /**
     * @notice Pauses the contract, preventing execution of functions with the notPaused modifier
     * @dev Can only be called by addresses with the EMERGENCY_MANAGER_ROLE
     */
    function pause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        require(!paused, EmergencyManager_AlreadyPaused());
        paused = true;
        emit Paused();
    }

    /**
     * @notice Unpauses the contract, allowing execution of functions with the notPaused modifier
     * @dev Can only be called by addresses with the EMERGENCY_MANAGER_ROLE
     */
    function unpause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        require(paused, EmergencyManager_NotPaused());
        paused = false;
        emit Unpaused();
    }

    /**
     * @notice Flag to allow skipping the safety buffer check on the next rebalance operation
     * @dev This can be used in emergency situations where the safety buffer check needs to be bypassed
     */
    function allowSkipNextRebalanceSafetyBufferCheck() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        require(
            !skipNextRebalanceSafetyBufferCheck, EmergencyManager_AlreadyAllowedToSkipNextRebalanceSafetyBufferCheck()
        );
        skipNextRebalanceSafetyBufferCheck = true;
        emit SkipNextRebalanceSafetyBufferCheckAllowed();
    }
}
