// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IACL as IACLBase} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IACL.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

interface IACL is IACLBase, IVersion {
    event CreateRole(bytes32 indexed role);
    event GrantRole(bytes32 indexed role, address indexed account);
    event RevokeRole(bytes32 indexed role, address indexed account);

    function getConfigurator() external view returns (address);
    function getRoles() external view returns (bytes32[] memory);
    function getRoleHolders(bytes32 role) external view returns (address[] memory);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
}
