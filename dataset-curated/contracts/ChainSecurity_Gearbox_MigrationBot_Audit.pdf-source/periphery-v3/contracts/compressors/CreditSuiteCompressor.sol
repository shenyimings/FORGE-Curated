// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {ICreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditConfiguratorV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IAdapter} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IAdapter.sol";

import {ICreditSuiteCompressor} from "../interfaces/ICreditSuiteCompressor.sol";

import {BaseLib} from "../libraries/BaseLib.sol";
import {AP_CREDIT_SUITE_COMPRESSOR} from "../libraries/Literals.sol";
import {ILegacyAdapter, Legacy} from "../libraries/Legacy.sol";

import {BaseState} from "../types/BaseState.sol";
import {
    AdapterState,
    CollateralToken,
    CreditFacadeState,
    CreditManagerState,
    CreditSuiteData
} from "../types/CreditSuiteData.sol";
import {CreditManagerFilter} from "../types/Filters.sol";

import {BaseCompressor} from "./BaseCompressor.sol";

contract CreditSuiteCompressor is BaseCompressor, ICreditSuiteCompressor {
    using BaseLib for address;

    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_CREDIT_SUITE_COMPRESSOR;

    constructor(address addressProvider_) BaseCompressor(addressProvider_) {}

    function getCreditSuites(CreditManagerFilter memory filter)
        external
        view
        override
        returns (CreditSuiteData[] memory result)
    {
        address[] memory creditManagers = _getCreditManagers(filter);
        result = new CreditSuiteData[](creditManagers.length);
        for (uint256 i; i < creditManagers.length; ++i) {
            result[i] = getCreditSuiteData(creditManagers[i]);
        }
    }

    function getCreditSuiteData(address creditManager) public view override returns (CreditSuiteData memory result) {
        result.creditManager = getCreditManagerState(creditManager);
        result.creditFacade = getCreditFacadeState(result.creditManager.creditFacade);
        result.creditConfigurator = getCreditConfiguratorState(result.creditManager.creditConfigurator);
        result.accountFactory = getAccountFactoryState(result.creditManager.accountFactory);
        result.adapters = getAdapters(creditManager);
    }

    function getCreditManagerState(address creditManager)
        public
        view
        override
        returns (CreditManagerState memory result)
    {
        result.underlying = ICreditManagerV3(creditManager).underlying();
        result.baseParams = creditManager.getBaseParams(_appendPostfix("CREDIT_MANAGER", result.underlying), address(0));

        result.name = ICreditManagerV3(creditManager).name();
        result.accountFactory = ICreditManagerV3(creditManager).accountFactory();
        result.pool = ICreditManagerV3(creditManager).pool();
        result.creditFacade = ICreditManagerV3(creditManager).creditFacade();
        result.creditConfigurator = ICreditManagerV3(creditManager).creditConfigurator();

        result.maxEnabledTokens = ICreditManagerV3(creditManager).maxEnabledTokens();

        uint256 collateralTokensCount = ICreditManagerV3(creditManager).collateralTokensCount();
        result.collateralTokens = new CollateralToken[](collateralTokensCount);
        for (uint256 i; i < collateralTokensCount; ++i) {
            (result.collateralTokens[i].token, result.collateralTokens[i].liquidationThreshold) =
                ICreditManagerV3(creditManager).collateralTokenByMask(1 << i);
        }

        (
            result.feeInterest,
            result.feeLiquidation,
            result.liquidationDiscount,
            result.feeLiquidationExpired,
            result.liquidationDiscountExpired
        ) = ICreditManagerV3(creditManager).fees();
    }

    function getCreditFacadeState(address creditFacade)
        public
        view
        override
        returns (CreditFacadeState memory result)
    {
        result.baseParams = creditFacade.getBaseParams("CREDIT_FACADE", address(0));

        result.degenNFT = ICreditFacadeV3(creditFacade).degenNFT();
        result.botList = ICreditFacadeV3(creditFacade).botList();

        result.expirable = ICreditFacadeV3(creditFacade).expirable();
        result.expirationDate = ICreditFacadeV3(creditFacade).expirationDate();

        result.maxDebtPerBlockMultiplier = ICreditFacadeV3(creditFacade).maxDebtPerBlockMultiplier();
        (result.minDebt, result.maxDebt) = ICreditFacadeV3(creditFacade).debtLimits();

        result.forbiddenTokensMask = ICreditFacadeV3(creditFacade).forbiddenTokenMask();

        result.isPaused = Pausable(creditFacade).paused();
    }

    function getCreditConfiguratorState(address creditConfigurator) public view override returns (BaseState memory) {
        return creditConfigurator.getBaseState("CREDIT_CONFIGURATOR", address(0));
    }

    function getAccountFactoryState(address accountFactory) public view override returns (BaseState memory) {
        return accountFactory.getBaseState("ACCOUNT_FACTORY::DEFAULT", address(0));
    }

    function getAdapters(address creditManager) public view override returns (AdapterState[] memory adapters) {
        address creditConfigurator = ICreditManagerV3(creditManager).creditConfigurator();
        address[] memory allowedAdapters = ICreditConfiguratorV3(creditConfigurator).allowedAdapters();
        adapters = new AdapterState[](allowedAdapters.length);
        for (uint256 i; i < allowedAdapters.length; ++i) {
            address adapter = allowedAdapters[i];
            adapters[i].baseParams.addr = adapter;

            try IAdapter(adapter).contractType() returns (bytes32 contractType_) {
                adapters[i].baseParams.contractType = contractType_;
            } catch {
                adapters[i].baseParams.contractType =
                    Legacy.getAdapterType(ILegacyAdapter(adapter)._gearboxAdapterType());
            }

            try IAdapter(adapter).version() returns (uint256 version_) {
                adapters[i].baseParams.version = version_;
            } catch {
                adapters[i].baseParams.version = ILegacyAdapter(adapter)._gearboxAdapterVersion();
            }

            try IAdapter(adapter).serialize() returns (bytes memory serializedParams) {
                adapters[i].baseParams.serializedParams = serializedParams;
            } catch {}

            adapters[i].targetContract = ICreditManagerV3(creditManager).adapterToContract(adapter);
        }
    }
}
