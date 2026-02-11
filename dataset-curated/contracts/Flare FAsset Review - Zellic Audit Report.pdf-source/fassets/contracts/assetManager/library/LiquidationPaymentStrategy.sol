// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Agents} from "./Agents.sol";
import {CollateralTypes} from "./CollateralTypes.sol";
import {Agent} from "./data/Agent.sol";
import {CollateralTypeInt} from "./data/CollateralTypeInt.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Globals} from "./Globals.sol";

library LiquidationPaymentStrategy {
    using Agents for Agent.State;
    using CollateralTypes for CollateralTypeInt.Data;

    // Liquidation premium step (depends on time, but is capped by the current collateral ratio)
    // assumed: agentStatus == LIQUIDATION/FULL_LIQUIDATION
    function currentLiquidationFactorBIPS(
        Agent.State storage _agent,
        uint256 _vaultCR,
        uint256 _poolCR
    )
        internal view
        returns (uint256 _c1FactorBIPS, uint256 _poolFactorBIPS)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        uint256 step = _currentLiquidationStep(_agent);
        uint256 factorBIPS = settings.liquidationCollateralFactorBIPS[step];
        // All premiums are expressed as factor BIPS.
        // Current algorithm for splitting payment: use liquidationCollateralFactorBIPS for vault collateral and
        // pay the rest from pool. If any factor exceeds the CR of that collateral, pay that collateral at
        // its CR and pay more of the other. If both collaterals exceed CR, limit both to their CRs.
        _c1FactorBIPS = Math.min(settings.liquidationFactorVaultCollateralBIPS[step], factorBIPS);
        // never exceed CR of tokens
        if (_c1FactorBIPS > _vaultCR) {
            _c1FactorBIPS = _vaultCR;
        }
        _poolFactorBIPS = factorBIPS - _c1FactorBIPS;
        if (_poolFactorBIPS > _poolCR) {
            _poolFactorBIPS = _poolCR;
            _c1FactorBIPS = Math.min(factorBIPS - _poolFactorBIPS, _vaultCR);
        }
    }

    // Liquidation premium step (depends on time since liquidation was started)
    // assumed: agentStatus == LIQUIDATION/FULL_LIQUIDATION
    function _currentLiquidationStep(
        Agent.State storage _agent
    )
        private view
        returns (uint256)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // calculate premium step based on time since liquidation started
        uint256 liquidationStart = _agent.liquidationStartedAt;
        uint256 step = (block.timestamp - liquidationStart) / settings.liquidationStepSeconds;
        return Math.min(step, settings.liquidationCollateralFactorBIPS.length - 1);
    }
}
