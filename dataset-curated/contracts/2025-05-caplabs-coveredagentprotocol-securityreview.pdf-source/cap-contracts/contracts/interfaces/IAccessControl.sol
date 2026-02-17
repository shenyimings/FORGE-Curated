// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title IAccessControl
/// @author kexley, @capLabs
/// @notice Interface for AccessControl contract
interface IAccessControl {
    /// @notice Initialize the default admin
    /// @param _admin Default admin address
    function initialize(address _admin) external;

    /// @notice Check a specific method access is granted to an address
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @param _caller Address to check role for
    function checkAccess(bytes4 _selector, address _contract, address _caller) external view;

    /// @notice Grant access to a specific method on a contract
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @param _address Address to grant role to
    function grantAccess(bytes4 _selector, address _contract, address _address) external;

    /// @notice Revoke access to a specific method on a contract
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @param _address Address to revoke role from
    function revokeAccess(bytes4 _selector, address _contract, address _address) external;

    /// @notice Fetch role id for a function selector on a contract
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @return roleId Role id
    function role(bytes4 _selector, address _contract) external pure returns (bytes32 roleId);
}
