// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {AgentPayout} from "../library/AgentPayout.sol";
import {Agents} from "../library/Agents.sol";
import {Conversion} from "../library/Conversion.sol";
import {Liquidation} from "../library/Liquidation.sol";
import {LiquidationPaymentStrategy} from "../library/LiquidationPaymentStrategy.sol";
import {Redemptions} from "../library/Redemptions.sol";
import {Agent} from "../library/data/Agent.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {Collateral} from "../library/data/Collateral.sol";
import {CollateralTypeInt} from "../library/data/CollateralTypeInt.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {AgentInfo} from "../../userInterfaces/data/AgentInfo.sol";
import {SafePct} from "../../utils/library/SafePct.sol";


contract LiquidationFacet is AssetManagerBase, ReentrancyGuard {
    using SafeCast for uint256;
    using SafePct for uint256;
    using Agent for Agent.State;

    error CannotStopLiquidation();
    error NotInLiquidation();
    error LiquidationNotStarted();
    error LiquidationNotPossible(AgentInfo.Status status);

    /**
     * Checks that the agent's collateral is too low and if true, starts agent's liquidation.
     * If the agent is already in liquidation, returns the timestamp when liquidation started.
     * @param _agentVault agent vault address
     * @return _liquidationStartTs timestamp when liquidation started
     */
    function startLiquidation(
        address _agentVault
    )
        external
        notEmergencyPaused
        nonReentrant
        returns (uint256 _liquidationStartTs)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        Liquidation.CRData memory cr = Liquidation.getCollateralRatiosBIPS(agent);
        bool inLiquidation = _startLiquidation(agent, cr);
        // check that liquidation was started
        require(inLiquidation, LiquidationNotStarted());
        _liquidationStartTs = agent.liquidationStartedAt;
    }

    /**
     * Burns up to `_amountUBA` f-assets owned by the caller and pays
     * the caller the corresponding amount of native currency with premium
     * (premium depends on the liquidation state).
     * If the agent isn't in liquidation yet, but satisfies conditions,
     * automatically puts the agent in liquidation status.
     * @param _agentVault agent vault address
     * @param _amountUBA the amount of f-assets to liquidate
     * @return _liquidatedAmountUBA liquidated amount of f-asset
     * @return _amountPaidVault amount paid to liquidator (in agent's vault collateral)
     * @return _amountPaidPool amount paid to liquidator (in NAT from pool)
     */
    function liquidate(
        address _agentVault,
        uint256 _amountUBA
    )
        external
        notEmergencyPaused
        nonReentrant
        returns (uint256 _liquidatedAmountUBA, uint256 _amountPaidVault, uint256 _amountPaidPool)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        // calculate both CRs
        Liquidation.CRData memory cr = Liquidation.getCollateralRatiosBIPS(agent);
        // allow one-step liquidation (without calling startLiquidation first)
        bool inLiquidation = _startLiquidation(agent, cr);
        require(inLiquidation, NotInLiquidation());
        // liquidate redemption tickets
        (uint64 liquidatedAmountAMG, uint256 payoutC1Wei, uint256 payoutPoolWei) =
            _performLiquidation(agent, cr, Conversion.convertUBAToAmg(_amountUBA));
        _liquidatedAmountUBA = Conversion.convertAmgToUBA(liquidatedAmountAMG);
        // pay the liquidator
        if (payoutC1Wei > 0) {
            _amountPaidVault = AgentPayout.payoutFromVault(agent, msg.sender, payoutC1Wei);
        }
        if (payoutPoolWei > 0) {
            uint256 agentResponsibilityWei = _agentResponsibilityWei(agent, payoutPoolWei);
            _amountPaidPool = AgentPayout.payoutFromPool(agent, msg.sender, payoutPoolWei, agentResponsibilityWei);
        }
        // if the agent was already safe due to price changes, there should be no LiquidationPerformed event
        // we do not revert, because it still marks agent as healthy (so there will still be a LiquidationEnded event)
        if (_liquidatedAmountUBA > 0) {
            // burn liquidated fassets
            Redemptions.burnFAssets(msg.sender, _liquidatedAmountUBA);
            // notify about liquidation
            emit IAssetManagerEvents.LiquidationPerformed(_agentVault, msg.sender,
                _liquidatedAmountUBA, _amountPaidVault, _amountPaidPool);
        }
        // try to pull agent out of liquidation
        Liquidation.endLiquidationIfHealthy(agent);
    }

    /**
     * When agent's collateral reaches safe level during liquidation, the liquidation
     * process can be stopped by calling this method.
     * Full liquidation (i.e. the liquidation triggered by illegal underlying payment)
     * cannot be stopped.
     * NOTE: anybody can call.
     * @param _agentVault agent vault address
     */
    function endLiquidation(
        address _agentVault
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        Agent.State storage agent = Agent.get(_agentVault);
        Liquidation.endLiquidationIfHealthy(agent);
        require(agent.status == Agent.Status.NORMAL, CannotStopLiquidation());
    }

    /**
     * If agent's status is NORMAL, check if any collateral is underwater and start liquidation.
     * If agent is already in (full) liquidation, just update collateral underwater flags.
     * @param _agent agent state
     * @param _cr collateral ratios data
     * @return _inLiquidation true if agent is in liquidation
     */
    function _startLiquidation(
        Agent.State storage _agent,
        Liquidation.CRData memory _cr
    )
        private
        returns (bool _inLiquidation)
    {
        Agent.Status status = _agent.status;
        if (status == Agent.Status.LIQUIDATION || status == Agent.Status.FULL_LIQUIDATION) {
            _inLiquidation = true;
        } else if (status != Agent.Status.NORMAL) {
            // if agent is not in normal status, it cannot be liquidated
            revert LiquidationNotPossible(Agents.getAgentStatus(_agent));
        }

        // if any collateral is underwater, set/update its flag
        bool vaultUnderwater = _isCollateralUnderwater(_cr.vaultCR, _agent.vaultCollateralIndex);
        if (vaultUnderwater) {
            _agent.collateralsUnderwater |= Agent.LF_VAULT;
        }
        bool poolUnderwater = _isCollateralUnderwater(_cr.poolCR, _agent.poolCollateralIndex);
        if (poolUnderwater) {
            _agent.collateralsUnderwater |= Agent.LF_POOL;
        }
        // if not in liquidation yet, check if any collateral is underwater and start liquidation
        if (!_inLiquidation && (vaultUnderwater || poolUnderwater)) {
            _inLiquidation = true;
            _agent.status = Agent.Status.LIQUIDATION;
            _agent.liquidationStartedAt = block.timestamp.toUint64();
            emit IAssetManagerEvents.LiquidationStarted(_agent.vaultAddress(), block.timestamp);
        }
    }

    function _isCollateralUnderwater(
        uint256 _collateralRatioBIPS,
        uint256 _collateralIndex
    )
        private view
        returns (bool)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        CollateralTypeInt.Data storage collateral = state.collateralTokens[_collateralIndex];
        return _collateralRatioBIPS < collateral.minCollateralRatioBIPS;
    }

     function _performLiquidation(
        Agent.State storage _agent,
        Liquidation.CRData memory _cr,
        uint64 _amountAMG
    )
        private
        returns (uint64 _liquidatedAMG, uint256 _payoutC1Wei, uint256 _payoutPoolWei)
    {
        // split liquidation payment between agent vault and pool
        (uint256 vaultFactor, uint256 poolFactor) =
            LiquidationPaymentStrategy.currentLiquidationFactorBIPS(_agent, _cr.vaultCR, _cr.poolCR);
        // calculate liquidation amount
        uint256 maxLiquidatedAMG = Math.max(
            Liquidation.maxLiquidationAmountAMG(_agent, _cr.vaultCR, vaultFactor, Collateral.Kind.VAULT),
            Liquidation.maxLiquidationAmountAMG(_agent, _cr.poolCR, poolFactor, Collateral.Kind.POOL));
        uint64 amountToLiquidateAMG = Math.min(maxLiquidatedAMG, _amountAMG).toUint64();
        // liquidate redemption tickets
        (_liquidatedAMG,) = Redemptions.closeTickets(_agent, amountToLiquidateAMG, true);
        // calculate payouts to liquidator
        _payoutC1Wei =
            Conversion.convertAmgToTokenWei(uint256(_liquidatedAMG).mulBips(vaultFactor), _cr.amgToC1WeiPrice);
        _payoutPoolWei =
            Conversion.convertAmgToTokenWei(uint256(_liquidatedAMG).mulBips(poolFactor), _cr.amgToPoolWeiPrice);
    }

    // Share of amount paid by pool that is the fault of the agent
    // (affects how many of the agent's pool tokens will be slashed).
    function _agentResponsibilityWei(
        Agent.State storage _agent,
        uint256 _amount
    )
        private view
        returns (uint256)
    {
        if (_agent.status == Agent.Status.FULL_LIQUIDATION || _agent.collateralsUnderwater == Agent.LF_VAULT) {
            return _amount;
        } else if (_agent.collateralsUnderwater == Agent.LF_POOL) {
            return 0;
        } else {    // both collaterals were underwater - only half responsibility assigned to agent
            return _amount / 2;
        }
    }
}
