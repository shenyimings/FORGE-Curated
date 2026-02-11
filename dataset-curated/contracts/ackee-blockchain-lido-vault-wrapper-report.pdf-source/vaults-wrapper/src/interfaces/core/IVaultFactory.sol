// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IVaultFactory {
    struct RoleAssignment {
        address account;
        bytes32 role;
    }

    // Events
    event VaultCreated(address indexed vault);
    event DashboardCreated(address indexed dashboard, address indexed vault, address indexed admin);

    // Errors
    error ZeroArgument(string argument);
    error InsufficientFunds();

    // Immutable getters
    function LIDO_LOCATOR() external view returns (address);

    function BEACON() external view returns (address);

    function DASHBOARD_IMPL() external view returns (address);

    // Public/external functions
    function createVaultWithDashboard(
        address _defaultAdmin,
        address _nodeOperator,
        address _nodeOperatorManager,
        uint256 _nodeOperatorFeeBP,
        uint256 _confirmExpiry,
        RoleAssignment[] calldata _roleAssignments
    ) external payable returns (address vault, address dashboard);

    function createVaultWithDashboardWithoutConnectingToVaultHub(
        address _defaultAdmin,
        address _nodeOperator,
        address _nodeOperatorManager,
        uint256 _nodeOperatorFeeBP,
        uint256 _confirmExpiry,
        RoleAssignment[] calldata _roleAssignments
    ) external returns (address vault, address dashboard);
}
