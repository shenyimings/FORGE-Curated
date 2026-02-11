// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {AgentCollateral} from "../library/AgentCollateral.sol";
import {Globals} from "../library/Globals.sol";
import {Liquidation} from "../library/Liquidation.sol";
import {Agents} from "../library/Agents.sol";
import {AgentUpdates} from "../library/AgentUpdates.sol";
import {Agent} from "../library/data/Agent.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {Collateral} from "../library/data/Collateral.sol";
import {IWNat} from "../../flareSmartContracts/interfaces/IWNat.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {CollateralType} from "../../userInterfaces/data/CollateralType.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";


contract AgentCollateralFacet is AssetManagerBase, ReentrancyGuard {
    using SafePct for uint256;
    using SafeCast for uint256;
    using AgentCollateral for Collateral.Data;
    using Agents for Agent.State;
    using AgentUpdates for Agent.State;

    error WithdrawalInvalidAgentStatus();
    error WithdrawalNotAnnounced();
    error WithdrawalMoreThanAnnounced();
    error WithdrawalNotAllowedYet();
    error WithdrawalTooLate();
    error WithdrawalCRTooLow();
    error WithdrawalValueTooHigh();

    error OnlyAgentVaultOrPool();
    error CollateralWithdrawalAnnounced();
    error FAssetNotTerminated();

    /**
     * Agent is going to withdraw `_valueNATWei` amount of collateral from agent vault.
     * This has to be announced and agent must then wait `withdrawalWaitMinSeconds` time.
     * After that time, agent can call withdraw(_valueNATWei) on agent vault.
     * NOTE: may only be called by the agent vault owner.
     * @param _agentVault agent vault address
     * @param _valueNATWei the amount to be withdrawn
     * @return _withdrawalAllowedAt the timestamp when the withdrawal can be made
     */
    function announceVaultCollateralWithdrawal(
        address _agentVault,
        uint256 _valueNATWei
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
        returns (uint256 _withdrawalAllowedAt)
    {
        return _announceWithdrawal(Collateral.Kind.VAULT, _agentVault, _valueNATWei);
    }

    /**
     * Agent is going to withdraw `_valueNATWei` amount of collateral from agent vault.
     * This has to be announced and agent must then wait `withdrawalWaitMinSeconds` time.
     * After that time, agent can call withdraw(_valueNATWei) on agent vault.
     * NOTE: may only be called by the agent vault owner.
     * @param _agentVault agent vault address
     * @param _valueNATWei the amount to be withdrawn
     * @return _redemptionAllowedAt the timestamp when the redemption can be made
     */
    function announceAgentPoolTokenRedemption(
        address _agentVault,
        uint256 _valueNATWei
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
        returns (uint256 _redemptionAllowedAt)
    {
        return _announceWithdrawal(Collateral.Kind.AGENT_POOL, _agentVault, _valueNATWei);
    }

    /**
     * Called by AgentVault when agent calls `withdraw()`.
     * NOTE: may only be called from an agent vault, not from an EOA address.
     * @param _amountWei the withdrawn amount
     */
    function beforeCollateralWithdrawal(
        IERC20 _token,
        uint256 _amountWei
    )
        external
        notFullyEmergencyPaused
    {
        Agent.State storage agent = Agent.get(msg.sender);
        Collateral.Kind kind;
        if (_token == agent.getVaultCollateralToken()) {
            kind = Collateral.Kind.VAULT;
        } else if (_token == agent.collateralPool.poolToken()) {
            kind = Collateral.Kind.AGENT_POOL;
        } else {
            return;     // we don't care about other token withdrawals from agent vault
        }
        Agent.WithdrawalAnnouncement storage withdrawal = agent.withdrawalAnnouncement(kind);
        Collateral.Data memory collateralData = AgentCollateral.singleCollateralData(agent, kind);
        // only agents that are not being liquidated can withdraw
        // however, if the agent is in FULL_LIQUIDATION and totally liquidated,
        // the withdrawals must still be possible, otherwise the collateral gets locked forever
        require(agent.status == Agent.Status.NORMAL || agent.totalBackedAMG() == 0, WithdrawalInvalidAgentStatus());
        require(withdrawal.allowedAt != 0, WithdrawalNotAnnounced());
        require(_amountWei <= withdrawal.amountWei, WithdrawalMoreThanAnnounced());
        require(block.timestamp >= withdrawal.allowedAt, WithdrawalNotAllowedYet());
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        require(block.timestamp <= withdrawal.allowedAt + settings.agentTimelockedOperationWindowSeconds,
            WithdrawalTooLate());
        // Check that withdrawal doesn't reduce CR below mintingCR (withdrawal is not executed yet, but it balances
        // with the withdrawal announcement that is still in effect).
        // This would be equivalent to `collateralData.freeCollateralWei >= 0` if freeCollateralWei was signed,
        // but actually freeCollateralWei always returns positive part, so it cannot be used in this test.
        require(collateralData.lockedCollateralWei(agent) <= collateralData.fullCollateral, WithdrawalCRTooLow());
        // (partially) clear withdrawal announcement
        uint256 remaining = withdrawal.amountWei - _amountWei;    // guarded by above require
        withdrawal.amountWei = uint128(remaining);
        if (remaining == 0) {
            withdrawal.allowedAt = 0;
        }
    }

    /**
     * Called by AgentVault or CollateralPool when there was a deposit.
     * May pull agent out of liquidation.
     * NOTE: may only be called from an agent vault or collateral pool, not from an EOA address.
     */
    function updateCollateral(
        address _agentVault,
        IERC20 _token
    )
        // no emergency pause check to allow change token / deposit collateral
        external
    {
        Agent.State storage agent = Agent.get(_agentVault);
        require(msg.sender == _agentVault || msg.sender == address(agent.collateralPool),
            OnlyAgentVaultOrPool());
        // try to pull agent out of liquidation
        if (agent.isCollateralToken(_token)) {
            Liquidation.endLiquidationIfHealthy(agent);
        }
    }

    /**
     * When current pool collateral token contract (WNat) is replaced by the method setPoolWNatCollateralType,
     * pools don't switch automatically. Instead, the agent must call this method that swaps old WNat tokens for
     * new ones and sets it for use by the pool.
     * NOTE: may only be called by the agent vault owner.
     */
    function upgradeWNatContract(
        uint256 _start,
        uint256 _end
    )
        external
        onlyImmediateGovernanceOrExecutor
    {
        (address[] memory agentVaults,) = Agents.getAllAgents(_start, _end);
        for (uint256 i = 0; i < agentVaults.length; i++) {
            _upgradeWNatContract(agentVaults[i]);
        }
    }

    function _upgradeWNatContract(
        address _agentVault
    )
        private
    {
        Agent.State storage agent = Agent.get(_agentVault);
        AssetManagerState.State storage state = AssetManagerState.get();
        IWNat wNat = IWNat(address(state.collateralTokens[state.poolCollateralIndex].token));
        // upgrade pool wnat
        if (agent.poolCollateralIndex != state.poolCollateralIndex) {
            agent.poolCollateralIndex = state.poolCollateralIndex;
            agent.collateralPool.upgradeWNatContract(wNat);
            emit IAssetManagerEvents.AgentCollateralTypeChanged(_agentVault,
                uint8(CollateralType.Class.POOL), address(wNat));
        }
    }

    function _announceWithdrawal(
        Collateral.Kind _kind,
        address _agentVault,
        uint256 _amountWei
    )
        private
        returns (uint256)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        // only agents that are not being liquidated can withdraw
        // however, if the agent is in FULL_LIQUIDATION and totally liquidated,
        // the withdrawals must still be possible, otherwise the collateral gets locked forever
        require(agent.status == Agent.Status.NORMAL || agent.totalBackedAMG() == 0, WithdrawalInvalidAgentStatus());
        Agent.WithdrawalAnnouncement storage withdrawal = agent.withdrawalAnnouncement(_kind);
        if (_amountWei > withdrawal.amountWei) {
            AssetManagerSettings.Data storage settings = Globals.getSettings();
            Collateral.Data memory collateralData = AgentCollateral.singleCollateralData(agent, _kind);
            // announcement increased - must check there is enough free collateral and then lock it
            // in this case the wait to withdrawal restarts from this moment
            uint256 increase = _amountWei - withdrawal.amountWei;
            require(increase <= collateralData.freeCollateralWei(agent), WithdrawalValueTooHigh());
            withdrawal.allowedAt = (block.timestamp + settings.withdrawalWaitMinSeconds).toUint64();
        } else {
            // announcement decreased or cancelled
            // if value is 0, we cancel announcement completely (i.e. set announcement time to 0)
            // otherwise, for decreasing announcement, we can safely leave announcement time unchanged
            if (_amountWei == 0) {
                withdrawal.allowedAt = 0;
            }
        }
        withdrawal.amountWei = _amountWei.toUint128();
        if (_kind == Collateral.Kind.VAULT) {
            emit IAssetManagerEvents.VaultCollateralWithdrawalAnnounced(_agentVault, _amountWei, withdrawal.allowedAt);
        } else {
            emit IAssetManagerEvents.PoolTokenRedemptionAnnounced(_agentVault, _amountWei, withdrawal.allowedAt);
        }
        return withdrawal.allowedAt;
    }
}