// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC5313.sol";
import "../../interfaces/ISingleAdminAccessControl.sol";

/**
 * @title SingleAdminAccessControl
 * @notice SingleAdminAccessControl is a contract that provides a single admin role with timelock
 * @notice This contract is a simplified alternative to OpenZeppelin's AccessControlDefaultAdminRules
 * @dev Added 3-day timelock for admin transfers
 */
abstract contract SingleAdminAccessControl is
    IERC5313,
    ISingleAdminAccessControl,
    AccessControl
{
    address private _currentDefaultAdmin;
    address private _pendingDefaultAdmin;

    // New variables for timelock
    uint256 public constant TIMELOCK_DELAY = 3 days;
    uint256 private _transferRequestTime;

    error TimelockNotExpired(uint256 remainingTime);
    error NoActiveTransferRequest();
    error TransferAlreadyInProgress();

    // Add this event to ISingleAdminAccessControl.sol
    event AdminTransferCancelled(
        address indexed currentAdmin,
        address indexed pendingAdmin
    );

    modifier notAdmin(bytes32 role) {
        if (role == DEFAULT_ADMIN_ROLE) revert InvalidAdminChange();
        _;
    }

    /// @notice Transfer the admin role to a new address
    /// @notice This can ONLY be executed by the current admin
    /// @notice Initiates a transfer request with a 3-day timelock
    /// @param newAdmin address of the new admin
    function transferAdmin(
        address newAdmin
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == msg.sender) revert InvalidAdminChange();
        if (newAdmin == address(0)) revert InvalidAdminChange();
        if (_transferRequestTime != 0) revert TransferAlreadyInProgress();

        _pendingDefaultAdmin = newAdmin;
        _transferRequestTime = block.timestamp;

        emit AdminTransferRequested(_currentDefaultAdmin, newAdmin);
    }

    /// @notice Cancel a pending admin transfer request
    /// @notice Can only be called by the current admin
    function cancelTransferAdmin() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_pendingDefaultAdmin == address(0))
            revert NoActiveTransferRequest();

        delete _pendingDefaultAdmin;
        delete _transferRequestTime;

        emit AdminTransferCancelled(_currentDefaultAdmin, _pendingDefaultAdmin);
    }

    /// @notice Accept the admin role transfer after timelock expires
    /// @notice Can only be called by the pending admin after the timelock period
    function acceptAdmin() external {
        if (msg.sender != _pendingDefaultAdmin) revert NotPendingAdmin();
        if (_transferRequestTime == 0) revert NoActiveTransferRequest();

        uint256 timeElapsed = block.timestamp - _transferRequestTime;
        if (timeElapsed < TIMELOCK_DELAY) {
            revert TimelockNotExpired(TIMELOCK_DELAY - timeElapsed);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Check the remaining time until a transfer can be accepted
    /// @return remaining time in seconds, 0 if no active transfer or if timelock has expired
    function getTransferTimelockStatus() external view returns (uint256) {
        if (_pendingDefaultAdmin == address(0) || _transferRequestTime == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - _transferRequestTime;
        if (timeElapsed >= TIMELOCK_DELAY) {
            return 0;
        }

        return TIMELOCK_DELAY - timeElapsed;
    }

    /// @notice grant a role
    /// @notice can only be executed by the current single admin
    /// @notice admin role cannot be granted externally
    /// @param role bytes32
    /// @param account address
    function grantRole(
        bytes32 role,
        address account
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) notAdmin(role) {
        _grantRole(role, account);
    }

    /// @notice revoke a role
    /// @notice can only be executed by the current admin
    /// @notice admin role cannot be revoked
    /// @param role bytes32
    /// @param account address
    function revokeRole(
        bytes32 role,
        address account
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) notAdmin(role) {
        _revokeRole(role, account);
    }

    /// @notice renounce the role of msg.sender
    /// @notice admin role cannot be renounced
    /// @param role bytes32
    /// @param account address
    function renounceRole(
        bytes32 role,
        address account
    ) public virtual override notAdmin(role) {
        super.renounceRole(role, account);
    }

    /**
     * @dev See {IERC5313-owner}.
     */
    function owner() public view virtual returns (address) {
        return _currentDefaultAdmin;
    }

    /**
     * @notice no way to change admin without removing old admin first
     */
    function _grantRole(
        bytes32 role,
        address account
    ) internal override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE) {
            emit AdminTransferred(_currentDefaultAdmin, account);
            _revokeRole(DEFAULT_ADMIN_ROLE, _currentDefaultAdmin);
            _currentDefaultAdmin = account;
            delete _pendingDefaultAdmin;
            delete _transferRequestTime;
        }
        return super._grantRole(role, account);
    }
}
