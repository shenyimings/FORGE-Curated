// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.22;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SelfCallable } from "./lib/SelfCallable.sol";

/**
 * @title ExecutorStore
 * @notice Abstract contract that manages a set of executors and a whether they are required.
 * @dev Uses EnumerableSet to store executor addresses
 */
abstract contract ExecutorStore is SelfCallable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Set of available executors for the MultiSig.
     */
    EnumerableSet.AddressSet internal executorSet;

    /**
     * @notice Whether the executor permission is required to execute a transaction.
     */
    bool public executorRequired;

    /// @notice Error thrown when an executor address is invalid.
    /// @dev This error is thrown when the address is zero.
    error InvalidExecutor();

    /// @notice Error thrown when attempting to add an execute who is already active.
    /// @param executor The address of the executor.
    error ExecutorAlreadyActive(address executor);

    /// @notice Error thrown when attempting to remove an execute who is not found.
    /// @param executor The address of the executor.
    error ExecutorNotFound(address executor);

    /**
     * @notice Emitted when an executor's active status is updated.
     * @param executor The address of the executor.
     * @param active True if added, false if removed.
     */
    event ExecutorSet(address indexed executor, bool active);

    /**
     * @notice Emitted when the executor required state is updated.
     * @param required The new state
     */
    event ExecutorRequiredSet(bool required);

    /**
     * @dev Initializes the ExecutorStore with a list of executors and sets whether executors are required.
     * @param _executors Array of executor addresses, can be empty.
     * @param _executorRequired The initial state of the executorRequired flag.
     */
    constructor(address[] memory _executors, bool _executorRequired) {
        for (uint256 i = 0; i < _executors.length; i++) {
            _addExecutor(_executors[i]);
        }
        _setExecutorRequired(_executorRequired);
    }

    /**
     * @dev Sets whether executors are required.
     * @param _executorRequired The new threshold value.
     */
    function setExecutorRequired(bool _executorRequired) external onlySelfCall {
        _setExecutorRequired(_executorRequired);
    }

    /**
     * @dev Internal function to set whether executors are required for this MultiSig.
     * @param _executorRequired The new value.
     */
    function _setExecutorRequired(bool _executorRequired) internal {
        executorRequired = _executorRequired;
        emit ExecutorRequiredSet(_executorRequired);
    }

    /**
     * @notice Adds or removes an executor from this MultiSig.
     * @dev Only callable via the MultiSig contract itself.
     * @param _executor The address of the executor to add/remove.
     * @param _active True to add executor, false to remove executor.
     */
    function setExecutor(address _executor, bool _active) external onlySelfCall {
        if (_active) {
            _addExecutor(_executor);
        } else {
            _removeExecutor(_executor);
        }
    }

    /**
     * @dev Internal function to add an executor.
     * @param _executor The address of the executor to add.
     */
    function _addExecutor(address _executor) internal {
        if (_executor == address(0)) revert InvalidExecutor();
        if (!executorSet.add(_executor)) revert ExecutorAlreadyActive(_executor);
        emit ExecutorSet(_executor, true);
    }

    /**
     * @dev Internal function to remove an executor.
     * @param _executor The address of the executor to remove.
     */
    function _removeExecutor(address _executor) internal {
        if (!executorSet.remove(_executor)) revert ExecutorNotFound(_executor);
        emit ExecutorSet(_executor, false);
    }

    /**
     * @notice Returns the list of all active executors.
     * @return An array of addresses representing the current set of executors.
     */
    function getExecutors() public view returns (address[] memory) {
        return executorSet.values();
    }

    /**
     * @notice Checks if a given address is in the set of executors.
     * @param _executor The address to check.
     * @return True if the address is a executor, otherwise false.
     */
    function isExecutor(address _executor) public view returns (bool) {
        return executorSet.contains(_executor);
    }

    /**
     * @notice Returns the total number of active executors.
     * @return The number of executors currently active.
     */
    function totalExecutors() public view returns (uint256) {
        return executorSet.length();
    }
}
