// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ConfigureDelegation } from "../contracts/deploy/service/ConfigureDelegation.sol";
import { ConfigureOracle } from "../contracts/deploy/service/ConfigureOracle.sol";

import { DeployVault } from "../contracts/deploy/service/DeployVault.sol";
import { LzAddressbook, LzUtils } from "../contracts/deploy/utils/LzUtils.sol";
import { ZapAddressbook, ZapUtils } from "../contracts/deploy/utils/ZapUtils.sol";
import { OracleMocksConfig } from "../test/deploy/interfaces/TestDeployConfig.sol";
import { DeployMocks } from "../test/deploy/service/DeployMocks.sol";

import {
    ImplementationsConfig,
    InfraConfig,
    LibsConfig,
    UsersConfig,
    VaultConfig
} from "../contracts/deploy/interfaces/DeployConfigs.sol";

import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { InfraConfigSerializer } from "./config/InfraConfigSerializer.sol";

import { VaultConfigSerializer } from "./config/VaultConfigSerializer.sol";
import { WalletUsersConfig } from "./config/WalletUsersConfig.sol";
import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";

contract DeployTestnetVault is
    Script,
    WalletUsersConfig,
    InfraConfigSerializer,
    VaultConfigSerializer,
    LzUtils,
    ZapUtils,
    DeployMocks,
    DeployVault,
    ConfigureOracle
{
    LzAddressbook lzAb;
    ZapAddressbook zapAb;

    UsersConfig users;
    InfraConfig infra;
    ImplementationsConfig implems;
    LibsConfig libs;
    address[] assetMocks;
    OracleMocksConfig oracleMocks;
    VaultConfig vault;

    function run() external {
        vm.startBroadcast();

        users = _getUsersConfig();
        lzAb = _getLzAddressbook();
        zapAb = _getZapAddressbook();
        (implems, libs, infra) = _readInfraConfig();

        assetMocks = new address[](3);
        assetMocks[0] = address(new MockERC20("USDT", "USDT", 6));
        assetMocks[1] = address(new MockERC20("USDC", "USDC", 6));
        assetMocks[2] = address(new MockERC20("USDx", "USDx", 18));
        oracleMocks = _deployOracleMocks(assetMocks);

        vault = _deployVault(implems, infra, "Cap USD", "cUSD", oracleMocks.assets);
        vault.lzperiphery = _deployVaultLzPeriphery(lzAb, zapAb, vault, users);

        /// ACCESS CONTROL
        _initVaultAccessControl(infra, vault, env.users);

        /// VAULT ORACLE
        _initVaultOracle(libs, infra, vault);

        /// ORACLE mocks configuration
        _initOracleMocks(oracleMocks);
        for (uint256 i = 0; i < oracleMocks.assets.length; i++) {
            _initChainlinkPriceOracle(libs, infra, oracleMocks.assets[i], oracleMocks.chainlinkPriceFeeds[i]);
            _initAaveRateOracle(libs, infra, oracleMocks.assets[i], oracleMocks.aaveDataProviders[i]);
        }

        /// LENDER
        _initVaultLender(vault, infra);

        _saveVaultConfig(vault);
        vm.stopBroadcast();
    }
}
