// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IVaultFactory} from "../../src/interfaces/core/IVaultFactory.sol";
import {MockDashboard} from "./MockDashboard.sol";
import {MockStakingVault} from "./MockStakingVault.sol";
import {MockVaultHub} from "./MockVaultHub.sol";
import {MockWstETH} from "./MockWstETH.sol";

contract MockVaultFactory is IVaultFactory {
    address public VAULT_HUB;
    address public immutable DASHBOARD_IMPL_ADDRESS;

    constructor(address _vaultHub) {
        VAULT_HUB = _vaultHub;
        // Deploy a dashboard implementation for role constants
        address steth = address(MockVaultHub(payable(_vaultHub)).LIDO());
        address wsteth = address(new MockWstETH(steth));
        DASHBOARD_IMPL_ADDRESS = address(new MockDashboard(steth, wsteth, _vaultHub, address(0), address(this)));
    }

    function LIDO_LOCATOR() external pure returns (address) {
        return address(0);
    }

    function BEACON() external pure returns (address) {
        return address(0);
    }

    function DASHBOARD_IMPL() external view returns (address) {
        return DASHBOARD_IMPL_ADDRESS;
    }

    function createVaultWithDashboard(
        address _admin,
        address /* _nodeOperator */,
        address /* _nodeOperatorManager */,
        uint256 /* _nodeOperatorFeeBP */,
        uint256 /* _confirmExpiry */,
        IVaultFactory.RoleAssignment[] memory _roleAssignments
    ) external payable returns (address vault, address dashboard) {
        if (msg.value != 1 ether) {
            revert InsufficientFunds();
        }
        vault = address(new MockStakingVault());
        address steth = address(MockVaultHub(payable(VAULT_HUB)).LIDO());
        address wsteth = address(new MockWstETH(steth));
        // Pass this contract as admin temporarily to be able to grant roles
        dashboard = address(new MockDashboard(steth, wsteth, VAULT_HUB, vault, address(this)));

        // Grant roles to accounts as specified
        for (uint256 i = 0; i < _roleAssignments.length; i++) {
            MockDashboard(payable(dashboard)).grantRole(_roleAssignments[i].role, _roleAssignments[i].account);
        }

        // Transfer admin role to the actual admin and revoke from this contract
        MockDashboard(payable(dashboard)).grantRole(0x00, _admin);
        MockDashboard(payable(dashboard)).revokeRole(0x00, address(this));

        // Send the connect deposit to the vault to simulate the real factory behavior
        (bool success,) = vault.call{value: msg.value}("");
        require(success, "Transfer to vault failed");

        return (vault, dashboard);
    }

    function createVaultWithDashboardWithoutConnectingToVaultHub(
        address _admin,
        address, /* _nodeOperator */
        address, /* _nodeOperatorManager */
        uint256, /* _nodeOperatorFeeBP */
        uint256, /* _confirmExpiry */
        RoleAssignment[] calldata /* _roleAssignments */
    ) external returns (address vault, address dashboard) {
        vault = address(new MockStakingVault());
        address steth = address(MockVaultHub(payable(VAULT_HUB)).LIDO());
        address wsteth = address(new MockWstETH(steth));
        dashboard = address(new MockDashboard(steth, wsteth, VAULT_HUB, vault, _admin));
        return (vault, dashboard);
    }
}
