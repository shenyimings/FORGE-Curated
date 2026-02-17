// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { Network } from "../../contracts/delegation/providers/symbiotic/Network.sol";
import { NetworkMiddleware } from "../../contracts/delegation/providers/symbiotic/NetworkMiddleware.sol";
import { TestDeployer } from "../../test/deploy/TestDeployer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBurnerRouter } from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";
import { console } from "forge-std/console.sol";

contract MiddlewareTest is TestDeployer {
    function setUp() public {
        _deployCapTestEnvironment();
        _initSymbioticVaultsLiquidity(env);

        // reset the initial stakes for this test
        {
            vm.startPrank(env.symbiotic.users.vault_admin);

            for (uint256 i = 0; i < env.testUsers.agents.length; i++) {
                address agent = env.testUsers.agents[i];
                _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, agent, 2e18);
                _symbioticVaultDelegateToAgent(symbioticUsdtVault, env.symbiotic.networkAdapter, agent, 1000e6);
            }

            _timeTravel(symbioticUsdtVault.vaultEpochDuration + 1 days);

            vm.stopPrank();
        }
    }

    function test_expect_the_current_stake_to_be_exposed() public {
        address agent = _getRandomAgent();

        {
            vm.startPrank(env.symbiotic.users.vault_admin);

            // remove all delegations to our slashable agent
            _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, agent, 0);
            _symbioticVaultDelegateToAgent(symbioticUsdtVault, env.symbiotic.networkAdapter, agent, 0);

            _timeTravel(10);

            // remove all delegations to our slashable agent
            _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, agent, 2e18);
            _symbioticVaultDelegateToAgent(symbioticUsdtVault, env.symbiotic.networkAdapter, agent, 1000e6);

            _timeTravel(10);

            vm.stopPrank();
        }

        // this is all within the same vault epoch
        //  |xxxxxxxxxx|----------|xxxxxxxxxx|
        //      2000   |    0     |    2000  |
        // -30        -20        -10         0

        assertEq(middleware.coverage(agent), 6200e8);
    }

    function test_current_agent_coverage_accounts_for_burner_router_changes() public {
        Network _network = Network(env.symbiotic.networkAdapter.network);

        address agent = _getRandomAgent();

        assertEq(middleware.coverage(agent), 6200e8);

        // vault admin changes the burner router receiver of the USDT vault
        {
            vm.startPrank(env.symbiotic.users.vault_admin);

            address new_receiver = makeAddr("new_receiver");
            IBurnerRouter(symbioticUsdtVault.burnerRouter).setNetworkReceiver(address(_network), new_receiver);

            _timeTravel(10);

            vm.stopPrank();
        }

        // current coverage must reflect that change
        assertEq(middleware.coverage(agent), 5200e8);
    }
}
