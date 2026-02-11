// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ConfigureAccessControl } from "../contracts/deploy/service/ConfigureAccessControl.sol";
import { DeployImplems } from "../contracts/deploy/service/DeployImplems.sol";
import { DeployInfra as DeployInfraService } from "../contracts/deploy/service/DeployInfra.sol";
import { DeployLibs } from "../contracts/deploy/service/DeployLibs.sol";

import { InfraConfigSerializer } from "./config/InfraConfigSerializer.sol";
import { WalletUsersConfig } from "./config/WalletUsersConfig.sol";

import {
    ImplementationsConfig,
    InfraConfig,
    LibsConfig,
    UsersConfig,
    VaultConfig
} from "../contracts/deploy/interfaces/DeployConfigs.sol";

import { Script } from "forge-std/Script.sol";

contract DeployInfra is
    Script,
    WalletUsersConfig,
    InfraConfigSerializer,
    DeployInfraService,
    DeployImplems,
    DeployLibs,
    ConfigureAccessControl
{
    string constant OUTPUT_PATH_FROM_PROJECT_ROOT = "config/cap-testnet-infra.json";

    UsersConfig users;
    ImplementationsConfig implems;
    LibsConfig libs;
    InfraConfig infra;

    function run() external {
        vm.startBroadcast();

        // Get the broadcast address (deployer's address)
        users = _getUsersConfig();
        implems = _deployImplementations();
        libs = _deployLibs();
        infra = _deployInfra(implems, users);

        _initInfraAccessControl(infra, users);

        _saveInfraConfig(implems, libs, infra);

        vm.stopBroadcast();
    }
}
