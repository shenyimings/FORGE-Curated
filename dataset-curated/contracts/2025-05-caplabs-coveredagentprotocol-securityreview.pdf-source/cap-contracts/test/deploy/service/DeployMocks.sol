// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { MockAaveDataProvider } from "../../mocks/MockAaveDataProvider.sol";
import { MockChainlinkPriceFeed } from "../../mocks/MockChainlinkPriceFeed.sol";
import { TestEnvConfig } from "../interfaces/TestDeployConfig.sol";

import { IDelegation } from "../../../contracts/interfaces/IDelegation.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockNetworkMiddleware } from "../../mocks/MockNetworkMiddleware.sol";
import { OracleMocksConfig, TestUsersConfig } from "../interfaces/TestDeployConfig.sol";
import { Vm } from "forge-std/Vm.sol";

contract DeployMocks {
    function _deployOracleMocks(address[] memory assets) internal returns (OracleMocksConfig memory d) {
        d.assets = assets;
        d.aaveDataProviders = new address[](assets.length);
        d.chainlinkPriceFeeds = new address[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            d.aaveDataProviders[i] = address(new MockAaveDataProvider());
            d.chainlinkPriceFeeds[i] = address(new MockChainlinkPriceFeed());
        }
    }

    function _initOracleMocks(OracleMocksConfig memory d, int256 latestAnswer, uint256 variableBorrowRate) internal {
        for (uint256 i = 0; i < d.assets.length; i++) {
            MockChainlinkPriceFeed(d.chainlinkPriceFeeds[i]).setDecimals(8);
            MockChainlinkPriceFeed(d.chainlinkPriceFeeds[i]).setLatestAnswer(latestAnswer);
            MockAaveDataProvider(d.aaveDataProviders[i]).setVariableBorrowRate(variableBorrowRate);
        }
    }

    function _deployUSDMocks() internal returns (address[] memory usdMocks) {
        usdMocks = new address[](3);
        usdMocks[0] = address(new MockERC20("USDT", "USDT", 6));
        usdMocks[1] = address(new MockERC20("USDC", "USDC", 6));
        usdMocks[2] = address(new MockERC20("USDx", "USDx", 18));
    }

    function _deployEthMocks() internal returns (address[] memory ethMocks) {
        ethMocks = new address[](1);
        ethMocks[0] = address(new MockERC20("WETH", "WETH", 18));
    }

    function _deployDelegationNetworkMock() internal returns (address delegationNetwork) {
        delegationNetwork = address(new MockNetworkMiddleware());
    }

    function _configureMockNetworkMiddleware(TestEnvConfig memory env, address delegationNetwork) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.startPrank(env.users.delegation_admin);
        IDelegation(env.infra.delegation).registerNetwork(delegationNetwork);

        for (uint256 i = 0; i < env.testUsers.agents.length; i++) {
            address agent = env.testUsers.agents[i];
            IDelegation(env.infra.delegation).addAgent(agent, delegationNetwork, 0.5e27, 0.7e27);
        }
    }

    function _setMockNetworkMiddlewareAgentCoverage(TestEnvConfig memory env, address agent, uint256 coverage)
        internal
    {
        MockNetworkMiddleware(env.symbiotic.networkAdapter.networkMiddleware).setMockCoverage(agent, coverage);
    }
}
