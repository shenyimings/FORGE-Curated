// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {MathUtils} from "../../utils/library/MathUtils.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Agents} from "./Agents.sol";
import {Conversion} from "./Conversion.sol";
import {AgentCollateral} from "./AgentCollateral.sol";
import {Agent} from "./data/Agent.sol";
import {Collateral} from "./data/Collateral.sol";
import {CollateralTypeInt} from "./data/CollateralTypeInt.sol";


library Liquidation {
    using SafeCast for uint256;
    using MathUtils for uint256;
    using SafePct for uint256;
    using Agent for Agent.State;
    using Agents for Agent.State;

    struct CRData {
        uint256 vaultCR;
        uint256 poolCR;
        uint256 amgToC1WeiPrice;
        uint256 amgToPoolWeiPrice;
    }

    // Start full agent liquidation (Agent.Status.FULL_LIQUIDATION)
    function startFullLiquidation(
        Agent.State storage _agent
    )
        internal
    {
        // if already in full liquidation or destroying, do nothing
        if (_agent.status == Agent.Status.FULL_LIQUIDATION
            || _agent.status == Agent.Status.DESTROYING) return;
        if (_agent.liquidationStartedAt == 0) {
            _agent.liquidationStartedAt = block.timestamp.toUint64();
        }
        _agent.status = Agent.Status.FULL_LIQUIDATION;
        emit IAssetManagerEvents.FullLiquidationStarted(_agent.vaultAddress(), block.timestamp);
    }

    // Cancel liquidation if the agent is healthy.
    function endLiquidationIfHealthy(
        Agent.State storage _agent
    )
        internal
    {
        // can only stop plain liquidation (full liquidation can only stop when there are no more minted assets)
        if (_agent.status != Agent.Status.LIQUIDATION) return;
        // agent's current collateral ratio
        CRData memory cr = getCollateralRatiosBIPS(_agent);
        // target ratio is minCollateralRatioBIPS if collateral not underwater, otherwise safetyMinCollateralRatioBIPS
        uint256 targetRatioVaultCollateralBIPS = _targetRatioBIPS(_agent, Collateral.Kind.VAULT);
        uint256 targetRatioPoolBIPS = _targetRatioBIPS(_agent, Collateral.Kind.POOL);
        // if agent is safe, restore status to NORMAL
        if (cr.vaultCR >= targetRatioVaultCollateralBIPS && cr.poolCR >= targetRatioPoolBIPS) {
            _agent.status = Agent.Status.NORMAL;
            _agent.liquidationStartedAt = 0;
            _agent.collateralsUnderwater = 0;
            emit IAssetManagerEvents.LiquidationEnded(_agent.vaultAddress());
        }
    }

    function getCollateralRatiosBIPS(
        Agent.State storage _agent
    )
        internal view
        returns (CRData memory)
    {
        (uint256 vaultCR, uint256 amgToC1WeiPrice) = getCollateralRatioBIPS(_agent, Collateral.Kind.VAULT);
        (uint256 poolCR, uint256 amgToPoolWeiPrice) = getCollateralRatioBIPS(_agent, Collateral.Kind.POOL);
        return CRData({
            vaultCR: vaultCR,
            poolCR: poolCR,
            amgToC1WeiPrice: amgToC1WeiPrice,
            amgToPoolWeiPrice: amgToPoolWeiPrice
        });
    }

    // The collateral ratio (BIPS) for deciding whether agent is in liquidation is the maximum
    // of the ratio calculated from FTSO price and the ratio calculated from trusted voters' price.
    // In this way, liquidation due to bad FTSO providers bunching together is less likely.
    function getCollateralRatioBIPS(
        Agent.State storage _agent,
        Collateral.Kind _collateralKind
    )
        internal view
        returns (uint256 _collateralRatioBIPS, uint256 _amgToTokenWeiPrice)
    {
        (Collateral.Data memory _data, Collateral.Data memory _trustedData) =
            _collateralDataWithTrusted(_agent, _collateralKind);
        uint256 ratio = AgentCollateral.collateralRatioBIPS(_data, _agent);
        uint256 ratioTrusted = AgentCollateral.collateralRatioBIPS(_trustedData, _agent);
        _amgToTokenWeiPrice = Math.min(_data.amgToTokenWeiPrice, _trustedData.amgToTokenWeiPrice);
        _collateralRatioBIPS = Math.max(ratio, ratioTrusted);
    }

    // Calculate the amount of liquidation that gets agent to safety.
    // assumed: agentStatus == LIQUIDATION/FULL_LIQUIDATION
    function maxLiquidationAmountAMG(
        Agent.State storage _agent,
        uint256 _collateralRatioBIPS,
        uint256 _factorBIPS,
        Collateral.Kind _collateralKind
    )
        internal view
        returns (uint256)
    {
        // for full liquidation, all minted amount can be liquidated
        if (_agent.status == Agent.Status.FULL_LIQUIDATION) {
            return _agent.mintedAMG;
        }
        // otherwise, liquidate just enough to get agent to safety
        uint256 targetRatioBIPS = _targetRatioBIPS(_agent, _collateralKind);
        if (targetRatioBIPS <= _collateralRatioBIPS) {
            return 0;               // agent already safe
        }
        if (_collateralRatioBIPS <= _factorBIPS) {
            return _agent.mintedAMG; // cannot achieve target - liquidate all
        }
        uint256 maxLiquidatedAMG = AgentCollateral.totalBackedAMG(_agent, _collateralKind)
            .mulDivRoundUp(targetRatioBIPS - _collateralRatioBIPS, targetRatioBIPS - _factorBIPS);
        return Math.min(maxLiquidatedAMG, _agent.mintedAMG);
    }

    function _targetRatioBIPS(
        Agent.State storage _agent,
        Collateral.Kind _collateralKind
    )
        private view
        returns (uint256)
    {
        CollateralTypeInt.Data storage collateral = _agent.getCollateral(_collateralKind);
        if (!_agent.collateralUnderwater(_collateralKind)) {
            return collateral.minCollateralRatioBIPS;
        } else {
            return collateral.safetyMinCollateralRatioBIPS;
        }
    }

    // Used for calculating liquidation collateral ratio.
    function _collateralDataWithTrusted(
        Agent.State storage _agent,
        Collateral.Kind _kind
    )
        private view
        returns (Collateral.Data memory _data, Collateral.Data memory _trustedData)
    {
        CollateralTypeInt.Data storage collateral = _agent.getCollateral(_kind);
        uint256 fullCollateral = _getCollateralAmount(_agent, _kind, collateral);
        (uint256 price, uint256 trusted) = Conversion.currentAmgPriceInTokenWeiWithTrusted(collateral);
        _data = Collateral.Data({ kind: _kind, fullCollateral: fullCollateral, amgToTokenWeiPrice: price });
        _trustedData = Collateral.Data({ kind: _kind, fullCollateral: fullCollateral, amgToTokenWeiPrice: trusted });
    }

    function _getCollateralAmount(
        Agent.State storage _agent,
        Collateral.Kind _kind,
        CollateralTypeInt.Data storage collateral
    )
        private view
        returns (uint256)
    {
        if (_kind == Collateral.Kind.POOL) {
            // Return tracked collateral amount in the pool.
            return _agent.collateralPool.totalCollateral();
        } else {
            // Return amount of vault collateral.
            return collateral.token.balanceOf(_agent.vaultAddress());
        }
    }
}
