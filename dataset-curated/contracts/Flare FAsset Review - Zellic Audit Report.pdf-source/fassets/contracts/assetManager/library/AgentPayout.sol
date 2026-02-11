// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IIAgentVault} from "../../agentVault/interfaces/IIAgentVault.sol";
import {Globals} from "./Globals.sol";
import {Agent} from "./data/Agent.sol";
import {CollateralTypeInt} from "./data/CollateralTypeInt.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Agents} from "./Agents.sol";


library AgentPayout {
    using Agent for Agent.State;

    function payoutFromVault(
        Agent.State storage _agent,
        address _receiver,
        uint256 _amountWei
    )
        internal
        returns (uint256 _amountPaid)
    {
        CollateralTypeInt.Data storage collateral = Agents.getVaultCollateral(_agent);
        // don't want the calling method to fail due to too small balance for payout
        IIAgentVault vault = IIAgentVault(_agent.vaultAddress());
        _amountPaid = Math.min(_amountWei, collateral.token.balanceOf(address(vault)));
        vault.payout(collateral.token, _receiver, _amountPaid);
    }

    function tryPayoutFromVault(
        Agent.State storage _agent,
        address _receiver,
        uint256 _amountWei
    )
        internal
        returns (bool _success, uint256 _amountPaid)
    {
        CollateralTypeInt.Data storage collateral = Agents.getVaultCollateral(_agent);
        // don't want the calling method to fail due to too small balance for payout
        IIAgentVault vault = IIAgentVault(_agent.vaultAddress());
        _amountPaid = Math.min(_amountWei, collateral.token.balanceOf(address(vault)));
        try vault.payout(collateral.token, _receiver, _amountPaid) {
            _success = true;
        } catch {
            _success = false;
            _amountPaid = 0;
        }
    }

    function payoutFromPool(
        Agent.State storage _agent,
        address _receiver,
        uint256 _amountWei,
        uint256 _agentResponsibilityWei
    )
        internal
        returns (uint256 _amountPaid)
    {
        // don't want the calling method to fail due to too small balance for payout
        uint256 poolBalance = _agent.collateralPool.totalCollateral();
        _amountPaid = Math.min(_amountWei, poolBalance);
        _agentResponsibilityWei = Math.min(_agentResponsibilityWei, _amountPaid);
        _agent.collateralPool.payout(_receiver, _amountPaid, _agentResponsibilityWei);
    }

    function payForConfirmationByOthers(
        Agent.State storage _agent,
        address _receiver
    )
        internal
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        uint256 amount = Agents.convertUSD5ToVaultCollateralWei(_agent, settings.confirmationByOthersRewardUSD5);
        payoutFromVault(_agent, _receiver, amount);
    }
}
