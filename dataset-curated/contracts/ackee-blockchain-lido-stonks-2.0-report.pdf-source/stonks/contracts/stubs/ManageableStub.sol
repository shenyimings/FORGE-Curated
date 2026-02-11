// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

/**
 * @title Management and ownership extension for the contracts
 * @notice Allows the owner of the contract to set the manager. When the manager is set
 *     Only the manager address may perform operations protected by the onlyManager() modifier.
 *     In the other case, anyone is allowed to call such methods.
 *     Only the owner is allowed to call a method protected by the onlyOwner() modifier, including
 *     setOwner() and setManager() methods.
 */
abstract contract ManageableStub {
    // ==================== Storage Variables ====================

    /// @notice Address of the contract owner with full administrative control.
    address public owner;
    /// @notice Address of the manager with restricted access to certain functions.
    address public manager;

    // ==================== Events ====================

    event ManagerSet(address newManager);
    event OwnerSet(address newOwner);

    // ==================== Errors ====================

    error NotOwner(address sender, address owner);
    error NotManager(address sender, address manager);

    // ==================== Constructor ====================

    constructor(address owner_, address manager_) {
        _setOwner(owner_);
        _setManager(manager_);
    }

    // ==================== Modifiers ====================

    /**
     * @notice Restricts function access to the owner.
     */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender, owner);
        }
        _;
    }

    /**
     * @notice When the owner sets the manager, msg.sender must be the manager address to
     *     pass the modifier check
     */
    modifier onlyManager() {
        if (manager != address(0) && manager != msg.sender) {
            revert NotManager(msg.sender, manager);
        }
        _;
    }

    // ==================== External Functions ====================

    /**
     * @notice Sets the manager address.
     * @param manager_ The address of the new manager.
     */
    function setManager(address manager_) external onlyOwner {
        _setManager(manager_);
    }

    /**
     * @notice Sets the owner address.
     * @param newOwner_ The address of the new owner.
     */
    function setOwner(address newOwner_) external onlyOwner {
        _setOwner(newOwner_);
    }

    // ==================== Internal Functions ====================

    function _setManager(address manager_) internal {
        manager = manager_;

        emit ManagerSet(manager_);
    }

    function _setOwner(address owner_) internal {
        owner = owner_;

        emit OwnerSet(owner_);
    }
}
