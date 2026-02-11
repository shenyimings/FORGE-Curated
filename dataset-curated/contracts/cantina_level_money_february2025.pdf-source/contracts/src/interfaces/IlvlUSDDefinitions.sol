// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

/// @dev Changelog: changed solidity version and name
interface IlvlUSDDefinitions {
    /// @notice This event is fired when the minter changes
    event MinterUpdated(address indexed newMinter, address indexed oldMinter);
    /// @notice This event is fired when the slasher changes
    event SlasherUpdated(
        address indexed newSlasher,
        address indexed oldSlasher
    );

    /// @notice Zero address not allowed
    error ZeroAddressException();
    /// @notice It's not possible to renounce the ownership
    error OperationNotAllowed();
    /// @notice Only the minter role can perform an action
    error OnlyMinter();
    /// @notice Address is denylisted
    error Denylisted();
    /// @notice Address is owner
    error IsOwner();
}
