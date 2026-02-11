// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Agent} from "./data/Agent.sol";
import {Liquidation} from "./Liquidation.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Globals} from "./Globals.sol";


library UnderlyingBalance {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafePct for uint256;
    using Agent for Agent.State;

    function updateBalance(
        Agent.State storage _agent,
        int256 _balanceChange
    )
        internal
    {
        int256 newBalance = _agent.underlyingBalanceUBA + _balanceChange;
        uint256 requiredBalance = requiredUnderlyingUBA(_agent);
        if (newBalance < requiredBalance.toInt256()) {
            emit IAssetManagerEvents.UnderlyingBalanceTooLow(_agent.vaultAddress(), newBalance, requiredBalance);
            Liquidation.startFullLiquidation(_agent);
        }
        _agent.underlyingBalanceUBA = newBalance.toInt128();
        emit IAssetManagerEvents.UnderlyingBalanceChanged(_agent.vaultAddress(), _agent.underlyingBalanceUBA);
    }

    // Like updateBalance, but it can never make balance negative and trigger liquidation.
    // Separate implementation to avoid dependency on liquidation for balance increases.
    function increaseBalance(
        Agent.State storage _agent,
        uint256 _balanceIncrease
    )
        internal
    {
        _agent.underlyingBalanceUBA += _balanceIncrease.toInt256().toInt128();
        emit IAssetManagerEvents.UnderlyingBalanceChanged(_agent.vaultAddress(), _agent.underlyingBalanceUBA);
    }

    // The minimum underlying balance that has to be held by the agent. Below this, agent is liquidated.
    // The only exception is that outstanding redemption payments can push the balance below by the redeemed amount.
    function requiredUnderlyingUBA(Agent.State storage _agent)
        internal view
        returns (uint256)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        return uint256(_agent.mintedAMG + _agent.redeemingAMG) * settings.assetMintingGranularityUBA;
    }
}
