// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ITadleMemory
 * @author Tadle Team
 * @notice Interface for interacting with TadleMemory contract
 * @dev Provides temporary storage functionality for cross-contract operations
 */
interface ITadleMemory {
    /// @notice Store a uint256 value with a specific ID
    /// @param _id Storage identifier
    /// @param _num Value to store
    function setUint(uint256 _id, uint256 _num) external;

    /// @notice Retrieve a uint256 value by ID
    /// @param _id Storage identifier
    /// @return _num Retrieved value
    function getUint(uint256 _id) external returns (uint256 _num);
}

/**
 * @title Stores
 * @author Tadle Team
 * @notice Base contract for managing temporary storage operations
 * @dev Provides utility functions for interacting with TadleMemory contract
 * @custom:storage Manages temporary data storage for connector operations
 */
contract Stores {
    // ============ Storage ============
    /// @dev Immutable reference to TadleMemory contract
    /// @notice Used for temporary storage operations
    ITadleMemory public immutable tadleMemory;

    /**
     * @dev Initialize contract with TadleMemory address
     * @param _memory Address of TadleMemory contract
     * @notice Sets up the contract with memory storage capability
     * @custom:validation Ensures memory address is not zero
     */
    constructor(address _memory) {
        require(_memory != address(0), "Stores: memory address cannot be zero");
        tadleMemory = ITadleMemory(_memory);
    }

    /**
     * @dev Get uint value from storage or use direct value
     * @param getId Storage ID for retrieval (0 means use direct value)
     * @param val Direct value to use if getId is 0
     * @return returnVal Retrieved value from storage or direct value
     * @notice Provides flexible value retrieval with fallback to direct value
     * @custom:conditional Uses storage if getId is non-zero, otherwise returns val
     */
    function getUint(
        uint256 getId,
        uint256 val
    ) internal virtual returns (uint256 returnVal) {
        returnVal = getId == 0 ? val : tadleMemory.getUint(getId);
    }

    /**
     * @dev Store uint value in storage if ID is provided
     * @param setId Storage ID (0 means skip storage)
     * @param val Value to store
     * @notice Conditionally stores value based on setId parameter
     * @custom:conditional Only stores if setId is non-zero
     * @custom:validation Prevents storing zero values
     */
    function setUint(uint256 setId, uint256 val) internal virtual {
        if (setId != 0) {
            require(val != 0, "Stores: cannot store zero value");
            tadleMemory.setUint(setId, val);
        }
    }
}
