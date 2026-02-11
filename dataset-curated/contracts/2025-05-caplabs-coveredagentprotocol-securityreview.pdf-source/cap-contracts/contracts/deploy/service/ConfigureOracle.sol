// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IOracle } from "../../interfaces/IOracle.sol";
import { Oracle } from "../../oracle/Oracle.sol";

import { AaveAdapter } from "../../oracle/libraries/AaveAdapter.sol";
import { CapTokenAdapter } from "../../oracle/libraries/CapTokenAdapter.sol";
import { ChainlinkAdapter } from "../../oracle/libraries/ChainlinkAdapter.sol";
import { StakedCapAdapter } from "../../oracle/libraries/StakedCapAdapter.sol";

import { InfraConfig, LibsConfig, VaultConfig } from "../interfaces/DeployConfigs.sol";

contract ConfigureOracle {
    function _initChainlinkPriceOracle(
        LibsConfig memory libs,
        InfraConfig memory infra,
        address asset,
        address priceFeed
    ) internal {
        IOracle.OracleData memory oracleData = IOracle.OracleData({
            adapter: libs.chainlinkAdapter,
            payload: abi.encodeWithSelector(ChainlinkAdapter.price.selector, priceFeed)
        });
        Oracle(infra.oracle).setPriceOracleData(asset, oracleData);
        Oracle(infra.oracle).setPriceBackupOracleData(asset, oracleData);
    }

    function _initAaveRateOracle(LibsConfig memory libs, InfraConfig memory infra, address asset, address dataProvider)
        internal
    {
        IOracle.OracleData memory oracleData = IOracle.OracleData({
            adapter: libs.aaveAdapter,
            payload: abi.encodeWithSelector(AaveAdapter.rate.selector, dataProvider, asset)
        });
        Oracle(infra.oracle).setMarketOracleData(asset, oracleData);
        Oracle(infra.oracle).setUtilizationOracleData(asset, oracleData);
        Oracle(infra.oracle).setBenchmarkRate(asset, uint256(0.15e27));
    }

    function _initRestakerRateForAgent(InfraConfig memory infra, address agent, uint256 rate) internal {
        Oracle(infra.oracle).setRestakerRate(agent, rate);
    }

    function _initVaultOracle(LibsConfig memory libs, InfraConfig memory infra, VaultConfig memory vault) internal {
        IOracle.OracleData memory cTokenOracleData = IOracle.OracleData({
            adapter: libs.capTokenAdapter,
            payload: abi.encodeWithSelector(CapTokenAdapter.price.selector, vault.capToken)
        });
        IOracle.OracleData memory stcTokenOracleData = IOracle.OracleData({
            adapter: libs.stakedCapAdapter,
            payload: abi.encodeWithSelector(StakedCapAdapter.price.selector, vault.stakedCapToken)
        });
        Oracle(infra.oracle).setPriceOracleData(vault.capToken, cTokenOracleData);
        Oracle(infra.oracle).setPriceOracleData(vault.stakedCapToken, stcTokenOracleData);
        Oracle(infra.oracle).setPriceBackupOracleData(vault.capToken, cTokenOracleData);
        Oracle(infra.oracle).setPriceBackupOracleData(vault.stakedCapToken, stcTokenOracleData);
    }
}
