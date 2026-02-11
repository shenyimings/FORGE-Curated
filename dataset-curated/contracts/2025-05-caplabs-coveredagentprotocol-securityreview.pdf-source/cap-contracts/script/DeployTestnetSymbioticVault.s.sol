// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { SymbioticVaultParams } from "../contracts/deploy/interfaces/SymbioticsDeployConfigs.sol";
import {
    SymbioticNetworkAdapterConfig,
    SymbioticNetworkAdapterImplementationsConfig,
    SymbioticNetworkRewardsConfig,
    SymbioticVaultConfig
} from "../contracts/deploy/interfaces/SymbioticsDeployConfigs.sol";

import { ConfigureDelegation } from "../contracts/deploy/service/ConfigureDelegation.sol";
import { ConfigureSymbioticOptIns } from "../contracts/deploy/service/providers/symbiotic/ConfigureSymbioticOptIns.sol";

import { DeployCapNetworkAdapter } from "../contracts/deploy/service/providers/symbiotic/DeployCapNetworkAdapter.sol";
import { DeploySymbioticVault } from "../contracts/deploy/service/providers/symbiotic/DeploySymbioticVault.sol";

import { LzAddressbook, LzUtils } from "../contracts/deploy/utils/LzUtils.sol";
import { SymbioticAddressbook, SymbioticUtils } from "../contracts/deploy/utils/SymbioticUtils.sol";

import {
    ImplementationsConfig,
    InfraConfig,
    LibsConfig,
    UsersConfig
} from "../contracts/deploy/interfaces/DeployConfigs.sol";

import { InfraConfigSerializer } from "./config/InfraConfigSerializer.sol";
import { SymbioticAdapterConfigSerializer } from "./config/SymbioticAdapterConfigSerializer.sol";
import { SymbioticVaultConfigSerializer } from "./config/SymbioticVaultConfigSerializer.sol";
import { WalletUsersConfig } from "./config/WalletUsersConfig.sol";

contract DeployTestnetSymbioticVault is
    Script,
    LzUtils,
    SymbioticUtils,
    WalletUsersConfig,
    ConfigureDelegation,
    DeploySymbioticVault,
    DeployCapNetworkAdapter,
    ConfigureSymbioticOptIns,
    InfraConfigSerializer,
    SymbioticAdapterConfigSerializer,
    SymbioticVaultConfigSerializer
{
    LzAddressbook lzAb;
    SymbioticAddressbook symbioticAb;

    UsersConfig users;
    InfraConfig infra;
    ImplementationsConfig implems;
    LibsConfig libs;

    SymbioticNetworkAdapterImplementationsConfig networkAdapterImplems;
    SymbioticNetworkAdapterConfig networkAdapter;

    SymbioticVaultConfig vault;
    SymbioticNetworkRewardsConfig rewards;

    function run() external {
        users = _getUsersConfig();
        (implems, libs, infra) = _readInfraConfig();
        address vault_admin = getWalletAddress();
        symbioticAb = _getSymbioticAddressbook();
        (networkAdapterImplems, networkAdapter) = _readSymbioticConfig();

        address collateral = vm.envAddress("COLLATERAL");

        address[] memory agents = new address[](1);
        agents[0] = getWalletAddress();

        vm.startBroadcast();

        console.log("deploying symbiotic vault");
        vault = _deploySymbioticVault(
            symbioticAb,
            SymbioticVaultParams({
                vault_admin: vault_admin,
                collateral: collateral,
                vaultEpochDuration: 1 hours,
                burnerRouterDelay: 0
            })
        );

        console.log("deploying symbiotic network rewards");
        rewards = _deploySymbioticRestakerRewardContract(symbioticAb, users, vault);
        _saveSymbioticConfig(vault, rewards);

        console.log("registering symbiotic network in vaults");
        _registerCapNetworkInVault(networkAdapter, vault);

        console.log("registering vaults in network middleware");
        for (uint256 i = 0; i < agents.length; i++) {
            _registerVaultsInNetworkMiddleware(networkAdapter, vault, rewards, agents[i]);
        }

        console.log("registering agents as operator");
        for (uint256 i = 0; i < agents.length; i++) {
            _agentRegisterAsOperator(symbioticAb);
            _agentOptInToSymbioticVault(symbioticAb, vault);
            _agentOptInToSymbioticNetwork(symbioticAb, networkAdapter);
        }

        console.log("registering vault to all agents");
        for (uint256 i = 0; i < agents.length; i++) {
            _networkOptInToSymbioticVault(networkAdapter, vault, agents[i]);
            _symbioticVaultDelegateToAgent(vault, networkAdapter, agents[i], 1e42);
        }

        console.log("init delegation");
        for (uint256 i = 0; i < agents.length; i++) {
            address agent = agents[i];
            _initDelegationAgent(infra, agent, networkAdapter.networkMiddleware);
        }

        vm.stopBroadcast();
    }
}
