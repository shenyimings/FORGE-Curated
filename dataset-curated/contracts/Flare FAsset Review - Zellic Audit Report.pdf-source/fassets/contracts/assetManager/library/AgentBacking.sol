// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AssetManagerState} from "./data/AssetManagerState.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Globals} from "./Globals.sol";
import {Conversion} from "./Conversion.sol";
import {Agent} from "./data/Agent.sol";
import {RedemptionQueue} from "./data/RedemptionQueue.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";


library AgentBacking {
    using Agent for Agent.State;
    using RedemptionQueue for RedemptionQueue.State;

    function releaseMintedAssets(
        Agent.State storage _agent,
        uint64 _valueAMG
    )
        internal
    {
        _agent.mintedAMG = _agent.mintedAMG - _valueAMG;
    }

    function startRedeemingAssets(
        Agent.State storage _agent,
        uint64 _valueAMG,
        bool _poolSelfCloseRedemption
    )
        internal
    {
        _agent.redeemingAMG += _valueAMG;
        if (!_poolSelfCloseRedemption) {
            _agent.poolRedeemingAMG += _valueAMG;
        }
        releaseMintedAssets(_agent, _valueAMG);
    }

    function endRedeemingAssets(
        Agent.State storage _agent,
        uint64 _valueAMG,
        bool _poolSelfCloseRedemption
    )
        internal
    {
        _agent.redeemingAMG = _agent.redeemingAMG - _valueAMG;
        if (!_poolSelfCloseRedemption) {
            _agent.poolRedeemingAMG = _agent.poolRedeemingAMG - _valueAMG;
        }
    }

    function createNewMinting(
        Agent.State storage _agent,
        uint64 _valueAMG
    )
        internal
    {
        // allocate minted assets
        _agent.mintedAMG += _valueAMG;

        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // Add value with dust, then take the whole number of lots from it to create the new ticket,
        // and the remainder as new dust. At the end, there will always be less than 1 lot of dust left.
        uint64 valueWithDustAMG = _agent.dustAMG + _valueAMG;
        uint64 newDustAMG = valueWithDustAMG % settings.lotSizeAMG;
        uint64 ticketValueAMG = valueWithDustAMG - newDustAMG;
        // create ticket and change dust
        if (ticketValueAMG > 0) {
            createRedemptionTicket(_agent, ticketValueAMG);
        }
        changeDust(_agent, newDustAMG);
    }

    function createRedemptionTicket(
        Agent.State storage _agent,
        uint64 _ticketValueAMG
    )
        internal
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        if (_ticketValueAMG == 0) return;
        address vaultAddress = _agent.vaultAddress();
        uint64 lastTicketId = state.redemptionQueue.lastTicketId;
        RedemptionQueue.Ticket storage lastTicket = state.redemptionQueue.getTicket(lastTicketId);
        if (lastTicket.agentVault == vaultAddress) {
            // last ticket is from the same agent - merge the new ticket with the last
            lastTicket.valueAMG += _ticketValueAMG;
            uint256 ticketValueUBA = Conversion.convertAmgToUBA(lastTicket.valueAMG);
            emit IAssetManagerEvents.RedemptionTicketUpdated(vaultAddress, lastTicketId, ticketValueUBA);
        } else {
            // either queue is empty or the last ticket belongs to another agent - create new ticket
            uint64 ticketId = state.redemptionQueue.createRedemptionTicket(vaultAddress, _ticketValueAMG);
            uint256 ticketValueUBA = Conversion.convertAmgToUBA(_ticketValueAMG);
            emit IAssetManagerEvents.RedemptionTicketCreated(vaultAddress, ticketId, ticketValueUBA);
        }
    }

    function changeDust(
        Agent.State storage _agent,
        uint64 _newDustAMG
    )
        internal
    {
        if (_agent.dustAMG == _newDustAMG) return;
        _agent.dustAMG = _newDustAMG;
        uint256 dustUBA = Conversion.convertAmgToUBA(_newDustAMG);
        emit IAssetManagerEvents.DustChanged(_agent.vaultAddress(), dustUBA);
    }

    function decreaseDust(
        Agent.State storage _agent,
        uint64 _dustDecreaseAMG
    )
        internal
    {
        uint64 newDustAMG = _agent.dustAMG - _dustDecreaseAMG;
        changeDust(_agent, newDustAMG);
    }
}