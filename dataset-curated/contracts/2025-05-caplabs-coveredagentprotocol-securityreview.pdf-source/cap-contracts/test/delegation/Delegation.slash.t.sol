// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IDelegation } from "../../contracts/interfaces/IDelegation.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";

import { console } from "forge-std/console.sol";

contract DelegationSlashTest is TestDeployer {
    address user_agent;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
        _initSymbioticVaultsLiquidity(env);

        user_agent = _getRandomAgent();

        vm.startPrank(env.symbiotic.users.vault_admin);
        _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, user_agent, 2e18);
        _symbioticVaultDelegateToAgent(symbioticUsdtVault, env.symbiotic.networkAdapter, user_agent, 1000e6);

        _timeTravel(30 days);
        vm.stopPrank();
    }

    function test_delegation_view_functions() public view {
        assertEq(delegation.epochDuration(), 1 days);
        assertEq(delegation.epoch(), block.timestamp / 1 days);
        assertEq(delegation.agents().length, 3);
        assertEq(delegation.networks(user_agent).length, 1);
        assertEq(delegation.globalDelegation(), 468186200e8);
        assertEq(delegation.slashableCollateral(user_agent), 2 * 2600e8 + 1000e8);
        assertEq(
            delegation.slashableCollateralByNetwork(user_agent, env.symbiotic.networkAdapter.networkMiddleware),
            2 * 2600e8 + 1000e8
        );
    }

    function test_slash_delegation() public {
        vm.startPrank(env.infra.lender);

        address liquidator = makeAddr("liquidator");

        /// USD Value of 620 of delegation
        delegation.slash(user_agent, liquidator, 620e8);

        assertApproxEqAbs(weth.balanceOf(liquidator), 2e17, 1);
        assertApproxEqAbs(usdt.balanceOf(liquidator), 100e6, 1);

        vm.stopPrank();
    }

    function test_delegation_management_functions() public {
        vm.startPrank(env.users.delegation_admin);

        address new_agent = makeAddr("new_agent");
        vm.expectRevert(IDelegation.AgentDoesNotExist.selector);
        delegation.modifyAgent(new_agent, 0.9e18, 0.8e18);

        delegation.addAgent(new_agent, 0.9e18, 0.8e18);

        vm.expectRevert(IDelegation.DuplicateAgent.selector);
        delegation.addAgent(new_agent, 0.9e18, 0.8e18);

        assertEq(delegation.ltv(new_agent), 0.9e18);
        assertEq(delegation.liquidationThreshold(new_agent), 0.8e18);

        delegation.registerNetwork(new_agent, env.symbiotic.networkAdapter.networkMiddleware);

        vm.expectRevert(IDelegation.DuplicateNetwork.selector);
        delegation.registerNetwork(new_agent, env.symbiotic.networkAdapter.networkMiddleware);

        vm.stopPrank();
        vm.startPrank(env.infra.lender);
        address fake_agent = makeAddr("fake_agent");
        vm.expectRevert();
        delegation.modifyAgent(fake_agent, 0.9e18, 0.8e18);

        vm.expectRevert();
        delegation.addAgent(fake_agent, 0.9e18, 0.8e18);

        vm.stopPrank();
    }
}
