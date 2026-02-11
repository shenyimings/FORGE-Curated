// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StvStETHPoolHarness} from "test/utils/StvStETHPoolHarness.sol";

/**
 * @title DashboardRolesTest
 * @notice Integration tests for Dashboard roles
 */
contract DashboardRolesTest is StvStETHPoolHarness {
    WrapperContext ctxMintEnabled;
    WrapperContext ctxMintDisabled;

    address nodeOperatorManager = NODE_OPERATOR;

    function setUp() public {
        _initializeCore();

        ctxMintEnabled = _deployStvStETHPool({enableAllowlist: false, nodeOperatorFeeBP: 200, reserveRatioGapBP: 500});
        ctxMintDisabled = _deployStvPool({enableAllowlist: false, nodeOperatorFeeBP: 200});
    }

    // Helpers

    function _fetchRoleHash(WrapperContext storage ctx, string memory roleName) internal view returns (bytes32) {
        bytes4 selector = bytes4(keccak256(abi.encodePacked(string.concat(roleName, "()"))));
        (bool ok, bytes memory result) = address(ctx.dashboard).staticcall(abi.encodePacked(selector));

        assertTrue(ok, "Failed to get role hash");
        return abi.decode(result, (bytes32));
    }

    function _assertRoleAssigned(WrapperContext storage ctx, string memory roleName, address expectedMember)
        internal
        view
    {
        bytes32 roleHash = _fetchRoleHash(ctx, roleName);
        assertEq(ctx.dashboard.getRoleMemberCount(roleHash), 1, string.concat(roleName, " member count mismatch"));
        assertEq(ctx.dashboard.getRoleMember(roleHash, 0), expectedMember, string.concat(roleName, " member mismatch"));
    }

    function _assertRoleNotAssigned(WrapperContext storage ctx, string memory roleName) internal view {
        bytes32 roleHash = _fetchRoleHash(ctx, roleName);
        assertEq(ctx.dashboard.getRoleMemberCount(roleHash), 0, string.concat(roleName, " member count mismatch"));
    }

    // Should be assign to the Timelock contract
    // - DEFAULT_ADMIN_ROLE

    function test_DashboardRoles_TimelockIsAdmin() public view {
        _assertRoleAssigned(ctxMintEnabled, "DEFAULT_ADMIN_ROLE", address(ctxMintEnabled.timelock));
        _assertRoleAssigned(ctxMintDisabled, "DEFAULT_ADMIN_ROLE", address(ctxMintDisabled.timelock));
    }

    // Should be assigned to the Node Operator Manager
    // - NODE_OPERATOR_MANAGER_ROLE

    function test_DashboardRoles_NodeOperatorManagerIsAssigned() public view {
        _assertRoleAssigned(ctxMintEnabled, "NODE_OPERATOR_MANAGER_ROLE", address(nodeOperatorManager));
        _assertRoleAssigned(ctxMintDisabled, "NODE_OPERATOR_MANAGER_ROLE", address(nodeOperatorManager));
    }

    // Should be assigned to the the Pool contract
    // - FUND_ROLE
    // - REBALANCE_ROLE

    function test_DashboardRoles_FundRoleIsAssigned() public view {
        _assertRoleAssigned(ctxMintEnabled, "FUND_ROLE", address(ctxMintEnabled.pool));
        _assertRoleAssigned(ctxMintDisabled, "FUND_ROLE", address(ctxMintDisabled.pool));
    }

    function test_DashboardRoles_RebalanceRoleIsAssigned() public view {
        _assertRoleAssigned(ctxMintEnabled, "REBALANCE_ROLE", address(ctxMintEnabled.pool));
        _assertRoleAssigned(ctxMintDisabled, "REBALANCE_ROLE", address(ctxMintDisabled.pool));
    }

    // Should be assigned to the Pool contract ONLY if minting is enabled
    // - MINT_ROLE
    // - BURN_ROLE

    function test_DashboardRoles_MintRoleIsAssigned() public view {
        _assertRoleAssigned(ctxMintEnabled, "MINT_ROLE", address(ctxMintEnabled.pool));
        _assertRoleNotAssigned(ctxMintDisabled, "MINT_ROLE");
    }

    function test_DashboardRoles_BurnRoleIsAssigned() public view {
        _assertRoleAssigned(ctxMintEnabled, "BURN_ROLE", address(ctxMintEnabled.pool));
        _assertRoleNotAssigned(ctxMintDisabled, "BURN_ROLE");
    }

    // Should be assigned to the WithdrawalQueue contract:
    // - WITHDRAW_ROLE

    function test_DashboardRoles_WithdrawalRoleIsAssigned() public view {
        _assertRoleAssigned(ctxMintEnabled, "WITHDRAW_ROLE", address(ctxMintEnabled.withdrawalQueue));
        _assertRoleAssigned(ctxMintDisabled, "WITHDRAW_ROLE", address(ctxMintDisabled.withdrawalQueue));
    }

    // Should not be assigned to anyone
    // - NODE_OPERATOR_UNGUARANTEED_DEPOSIT_ROLE - can be assigned from node operator manager
    // - NODE_OPERATOR_PROVE_UNKNOWN_VALIDATOR_ROLE - can be assigned from node operator manager
    // - NODE_OPERATOR_FEE_EXEMPT_ROLE - can be assigned from node operator manager
    // - VOLUNTARY_DISCONNECT_ROLE - can be assigned from timelock

    function test_DashboardRoles_UnguaranteedRoleIsNotAssigned() public view {
        _assertRoleNotAssigned(ctxMintEnabled, "NODE_OPERATOR_UNGUARANTEED_DEPOSIT_ROLE");
        _assertRoleNotAssigned(ctxMintDisabled, "NODE_OPERATOR_UNGUARANTEED_DEPOSIT_ROLE");
    }

    function test_DashboardRoles_ProveUnknownValidatorRoleIsNotAssigned() public view {
        _assertRoleNotAssigned(ctxMintEnabled, "NODE_OPERATOR_PROVE_UNKNOWN_VALIDATOR_ROLE");
        _assertRoleNotAssigned(ctxMintDisabled, "NODE_OPERATOR_PROVE_UNKNOWN_VALIDATOR_ROLE");
    }

    function test_DashboardRoles_FeeExemptRoleIsNotAssigned() public view {
        _assertRoleNotAssigned(ctxMintEnabled, "NODE_OPERATOR_FEE_EXEMPT_ROLE");
        _assertRoleNotAssigned(ctxMintDisabled, "NODE_OPERATOR_FEE_EXEMPT_ROLE");
    }

    function test_DashboardRoles_VoluntaryDisconnectRoleIsNotAssigned() public view {
        _assertRoleNotAssigned(ctxMintEnabled, "VOLUNTARY_DISCONNECT_ROLE");
        _assertRoleNotAssigned(ctxMintDisabled, "VOLUNTARY_DISCONNECT_ROLE");
    }

    // Can be assigned:
    // - COLLECT_VAULT_ERC20_ROLE
    // - VAULT_CONFIGURATION_ROLE
    // - REQUEST_VALIDATOR_EXIT_ROLE
    // - TRIGGER_VALIDATOR_WITHDRAWAL_ROLE
    // - PAUSE_BEACON_CHAIN_DEPOSITS_ROLE
    // - RESUME_BEACON_CHAIN_DEPOSITS_ROLE
}
