// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeMath64} from "../../utils/library/SafeMath64.sol";
import {Transfers} from "../../utils/library/Transfers.sol";
import {AssetManagerState} from "./data/AssetManagerState.sol";
import {Conversion} from "./Conversion.sol";
import {AgentBacking} from "./AgentBacking.sol";
import {Agent} from "../../assetManager/library/data/Agent.sol";
import {RedemptionQueue} from "./data/RedemptionQueue.sol";
import {Redemption} from "./data/Redemption.sol";
import {Globals} from "./Globals.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";


library Redemptions {
    using Agent for Agent.State;
    using RedemptionQueue for RedemptionQueue.State;

    error InvalidRequestId();

    function closeTickets(
        Agent.State storage _agent,
        uint64 _amountAMG,
        bool _immediatelyReleaseMinted
    )
        internal
        returns (uint64 _closedAMG, uint256 _closedUBA)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        // redemption tickets
        uint256 maxRedeemedTickets = Globals.getSettings().maxRedeemedTickets;
        uint64 lotSize = Globals.getSettings().lotSizeAMG;
        for (uint256 i = 0; i < maxRedeemedTickets && _closedAMG < _amountAMG; i++) {
            // each loop, firstTicketId will change since we delete the first ticket
            uint64 ticketId = state.redemptionQueue.agents[_agent.vaultAddress()].firstTicketId;
            if (ticketId == 0) {
                break;  // no more tickets for this agent
            }
            RedemptionQueue.Ticket storage ticket = state.redemptionQueue.getTicket(ticketId);
            uint64 maxTicketRedeemAMG = ticket.valueAMG + _agent.dustAMG;
            maxTicketRedeemAMG -= maxTicketRedeemAMG % lotSize; // round down to whole lots
            uint64 ticketRedeemAMG = SafeMath64.min64(_amountAMG - _closedAMG, maxTicketRedeemAMG);
            // only remove from tickets and add to total, do everything else after the loop
            removeFromTicket(ticketId, ticketRedeemAMG);
            _closedAMG += ticketRedeemAMG;
        }
        // now close the dust if anything remains (e.g. if there were not enough tickets to redeem)
        uint64 closeDustAMG = SafeMath64.min64(_amountAMG - _closedAMG, _agent.dustAMG);
        if (closeDustAMG > 0) {
            _closedAMG += closeDustAMG;
            AgentBacking.decreaseDust(_agent, closeDustAMG);
        }
        // self-close or liquidation is one step, so we can release minted assets without redeeming step
        if (_immediatelyReleaseMinted) {
            AgentBacking.releaseMintedAssets(_agent, _closedAMG);
        }
        // return
        _closedUBA = Conversion.convertAmgToUBA(_closedAMG);
    }

    function removeFromTicket(
        uint64 _redemptionTicketId,
        uint64 _redeemedAMG
    )
        internal
    {
        RedemptionQueue.State storage redemptionQueue = AssetManagerState.get().redemptionQueue;
        RedemptionQueue.Ticket storage ticket = redemptionQueue.getTicket(_redemptionTicketId);
        Agent.State storage agent = Agent.get(ticket.agentVault);
        uint64 lotSize = Globals.getSettings().lotSizeAMG;
        uint64 remainingAMG = ticket.valueAMG + agent.dustAMG - _redeemedAMG;
        uint64 remainingAMGDust = remainingAMG % lotSize;
        uint64 remainingAMGLots = remainingAMG - remainingAMGDust;
        if (remainingAMGLots == 0) {
            redemptionQueue.deleteRedemptionTicket(_redemptionTicketId);
            emit IAssetManagerEvents.RedemptionTicketDeleted(agent.vaultAddress(), _redemptionTicketId);
        } else if (remainingAMGLots != ticket.valueAMG) {
            ticket.valueAMG = remainingAMGLots;
            uint256 remainingUBA = Conversion.convertAmgToUBA(remainingAMGLots);
            emit IAssetManagerEvents.RedemptionTicketUpdated(agent.vaultAddress(), _redemptionTicketId, remainingUBA);
        }
        AgentBacking.changeDust(agent, remainingAMGDust);
    }

    function burnFAssets(
        address _owner,
        uint256 _amountUBA
    )
        internal
    {
        Globals.getFAsset().burn(_owner, _amountUBA);
    }

    // pay executor for executor calls in WNat, otherwise burn executor fee
    function payOrBurnExecutorFee(
        Redemption.Request storage _request
    )
        internal
    {
        uint256 executorFeeNatWei = _request.executorFeeNatGWei * Conversion.GWEI;
        if (executorFeeNatWei > 0) {
            _request.executorFeeNatGWei = 0;
            if (msg.sender == _request.executor) {
                Transfers.depositWNat(Globals.getWNat(), _request.executor, executorFeeNatWei);
            } else {
                Globals.getBurnAddress().transfer(executorFeeNatWei);
            }
        }
    }

    // burn executor fee
    function burnExecutorFee(
        Redemption.Request storage _request
    )
        internal
    {
        uint256 executorFeeNatWei = _request.executorFeeNatGWei * Conversion.GWEI;
        if (executorFeeNatWei > 0) {
            _request.executorFeeNatGWei = 0;
            Globals.getBurnAddress().transfer(executorFeeNatWei);
        }
    }

    function reCreateRedemptionTicket(
        Agent.State storage _agent,
        Redemption.Request storage _request
    )
        internal
    {
        AgentBacking.endRedeemingAssets(_agent, _request.valueAMG, _request.poolSelfClose);
        AgentBacking.createNewMinting(_agent, _request.valueAMG);
    }

    function finishRedemptionRequest(
        uint256 _redemptionRequestId,
        Redemption.Request storage _request,
        Redemption.Status _status
    )
        internal
    {
        assert(_status >= Redemption.Status.SUCCESSFUL);    // must be a final status
        _request.status = _status;
        releaseTransferToCoreVault(_redemptionRequestId, _request);
    }

    function releaseTransferToCoreVault(
        uint256 _redemptionRequestId,
        Redemption.Request storage _request
    )
        internal
    {
        if (_request.transferToCoreVault) {
            Agent.State storage agent = Agent.get(_request.agentVault);
            if (agent.activeTransferToCoreVault == _redemptionRequestId) {
                agent.activeTransferToCoreVault = 0;
            }
        }
    }

    function getRedemptionRequest(
        uint256 _redemptionRequestId,
        bool _requireUnconfirmed
    )
        internal view
        returns (Redemption.Request storage _request)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        require(_redemptionRequestId != 0, InvalidRequestId());
        _request = state.redemptionRequests[_redemptionRequestId];
        if (_requireUnconfirmed) {
            require(isOpen(_request), InvalidRequestId());
        } else {
            require(_request.status != Redemption.Status.EMPTY, InvalidRequestId());
        }
    }

    // true if redemption is valid and has not been confirmed yet
    function isOpen(Redemption.Request storage _request)
        internal view
        returns (bool)
    {
        Redemption.Status status = _request.status;
        return status == Redemption.Status.ACTIVE || status == Redemption.Status.DEFAULTED;
    }
}