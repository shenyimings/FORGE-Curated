// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2024
pragma solidity ^0.8.23;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IACL} from "../interfaces/IACL.sol";
import {AP_ACL} from "../libraries/ContractLiterals.sol";

/// @title Access control list
contract ACL is IACL, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_ACL;

    /// @dev Set of all existing roles
    EnumerableSet.Bytes32Set internal _roles;

    /// @dev Set of accounts that have been granted role `role`
    mapping(bytes32 role => EnumerableSet.AddressSet) internal _roleHolders;

    /// @notice Constructor
    /// @param owner_ Initial owner
    constructor(address owner_) {
        _transferOwnership(owner_);
    }

    /// @notice Returns configurator
    function getConfigurator() external view override returns (address) {
        return owner();
    }

    /// @notice Whether `account` is configurator
    function isConfigurator(address account) external view override returns (bool) {
        return account == owner();
    }

    /// @notice Returns the list of all existing roles
    function getRoles() external view override returns (bytes32[] memory) {
        return _roles.values();
    }

    /// @notice Returns the list of accounts that have been granted role `role`
    function getRoleHolders(bytes32 role) external view override returns (address[] memory) {
        return _roleHolders[role].values();
    }

    /// @notice Whether account `account` has been granted role `role`
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return _roleHolders[role].contains(account);
    }

    /// @notice Grants role `role` to account `account`
    /// @dev Reverts if caller is not configurator
    function grantRole(bytes32 role, address account) external override onlyOwner {
        if (_roles.add(role)) emit CreateRole(role);
        if (_roleHolders[role].add(account)) emit GrantRole(role, account);
    }

    /// @notice Revokes role `role` from account `account`
    /// @dev Reverts if caller is not configurator
    function revokeRole(bytes32 role, address account) external override onlyOwner {
        if (_roleHolders[role].remove(account)) emit RevokeRole(role, account);
    }
}
