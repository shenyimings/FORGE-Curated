// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPayment} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {Agents} from "../library/Agents.sol";
import {AgentPayout} from "../library/AgentPayout.sol";
import {Globals} from "../library/Globals.sol";
import {TransactionAttestation} from "../library/TransactionAttestation.sol";
import {UnderlyingBalance} from "../library/UnderlyingBalance.sol";
import {Agent} from "../library/data/Agent.sol";
import {PaymentConfirmations} from "../library/data/PaymentConfirmations.sol";
import {PaymentReference} from "../library/data/PaymentReference.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {UnderlyingBlockUpdater} from "../library/UnderlyingBlockUpdater.sol";


contract UnderlyingBalanceFacet is AssetManagerBase, ReentrancyGuard {
    using SafeCast for uint256;
    using PaymentConfirmations for PaymentConfirmations.State;

    error WrongAnnouncedPaymentSource();
    error WrongAnnouncedPaymentReference();
    error NoActiveAnnouncement();
    error AnnouncedUnderlyingWithdrawalActive();
    error TopupBeforeAgentCreated();
    error NotATopupPayment();
    error NotUnderlyingAddress();

    /**
     * When the agent tops up his underlying address, it has to be confirmed by calling this method,
     * which updates the underlying free balance value.
     * NOTE: may only be called by the agent vault owner.
     * @param _payment proof of the underlying payment; must include payment
     *      reference of the form `0x4642505266410011000...0<agents_vault_address>`
     * @param _agentVault agent vault address
     */
    function confirmTopupPayment(
        IPayment.Proof calldata _payment,
        address _agentVault
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        AssetManagerState.State storage state = AssetManagerState.get();
        TransactionAttestation.verifyPaymentSuccess(_payment);
        require(_payment.data.responseBody.receivingAddressHash == agent.underlyingAddressHash,
            NotUnderlyingAddress());
        require(_payment.data.responseBody.standardPaymentReference == PaymentReference.topup(_agentVault),
            NotATopupPayment());
        require(_payment.data.responseBody.blockNumber > agent.underlyingBlockAtCreation,
            TopupBeforeAgentCreated());
        state.paymentConfirmations.confirmIncomingPayment(_payment);
        // update state
        uint256 amountUBA = SafeCast.toUint256(_payment.data.responseBody.receivedAmount);
        UnderlyingBalance.increaseBalance(agent, amountUBA.toUint128());
        // update underlying block
        UnderlyingBlockUpdater.updateCurrentBlockForVerifiedPayment(_payment);
        // notify
        emit IAssetManagerEvents.UnderlyingBalanceToppedUp(_agentVault, _payment.data.requestBody.transactionId,
            amountUBA);
    }

    /**
     * Announce withdrawal of underlying currency.
     * In the event UnderlyingWithdrawalAnnounced the agent receives payment reference, which must be
     * added to the payment, otherwise it can be challenged as illegal.
     * Until the announced withdrawal is performed and confirmed or cancelled, no other withdrawal can be announced.
     * NOTE: may only be called by the agent vault owner.
     * @param _agentVault agent vault address
     */
    function announceUnderlyingWithdrawal(
        address _agentVault
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        Agent.State storage agent = Agent.get(_agentVault);
        require(agent.announcedUnderlyingWithdrawalId == 0, AnnouncedUnderlyingWithdrawalActive());
        state.newPaymentAnnouncementId += PaymentReference.randomizedIdSkip();
        uint64 announcementId = state.newPaymentAnnouncementId;
        agent.announcedUnderlyingWithdrawalId = announcementId;
        agent.underlyingWithdrawalAnnouncedAt = block.timestamp.toUint64();
        bytes32 paymentReference = PaymentReference.announcedWithdrawal(announcementId);
        emit IAssetManagerEvents.UnderlyingWithdrawalAnnounced(_agentVault, announcementId, paymentReference);
    }

    /**
     * Agent must provide confirmation of performed underlying withdrawal, which updates free balance with used gas
     * and releases announcement so that a new one can be made.
     * If the agent doesn't call this method, anyone can call it after a time (confirmationByOthersAfterSeconds).
     * NOTE: may only be called by the owner of the agent vault
     *   except if enough time has passed without confirmation - then it can be called by anybody.
     * @param _payment proof of the underlying payment
     * @param _agentVault agent vault address
     */
    function confirmUnderlyingWithdrawal(
        IPayment.Proof calldata _payment,
        address _agentVault
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        TransactionAttestation.verifyPayment(_payment);
        Agent.State storage agent = Agent.get(_agentVault);
        bool isAgent = Agents.isOwner(agent, msg.sender);
        uint64 announcementId = agent.announcedUnderlyingWithdrawalId;
        require(announcementId != 0, NoActiveAnnouncement());
        bytes32 paymentReference = PaymentReference.announcedWithdrawal(announcementId);
        require(_payment.data.responseBody.standardPaymentReference == paymentReference,
            WrongAnnouncedPaymentReference());
        require(_payment.data.responseBody.sourceAddressHash == agent.underlyingAddressHash,
            WrongAnnouncedPaymentSource());
        require(isAgent || block.timestamp >
                agent.underlyingWithdrawalAnnouncedAt + settings.confirmationByOthersAfterSeconds,
                Agents.OnlyAgentVaultOwner());
        // make sure withdrawal cannot be challenged as invalid
        state.paymentConfirmations.confirmSourceDecreasingTransaction(_payment);
        // clear active withdrawal announcement
        agent.announcedUnderlyingWithdrawalId = 0;
        // update free underlying balance and trigger liquidation if negative
        UnderlyingBalance.updateBalance(agent, -_payment.data.responseBody.spentAmount);
        // if the confirmation was done by someone else than agent, pay some reward from agent's vault
        if (!isAgent) {
            AgentPayout.payForConfirmationByOthers(agent, msg.sender);
        }
        // update underlying block
        UnderlyingBlockUpdater.updateCurrentBlockForVerifiedPayment(_payment);
        // send event
        emit IAssetManagerEvents.UnderlyingWithdrawalConfirmed(_agentVault, announcementId,
            _payment.data.responseBody.spentAmount, _payment.data.requestBody.transactionId);
    }

    /**
     * Cancel ongoing withdrawal of underlying currency.
     * Needed in order to reset announcement timestamp, so that others cannot front-run agent at
     * confirmUnderlyingWithdrawal call. This could happen if withdrawal would be performed more
     * than confirmationByOthersAfterSeconds seconds after announcement.
     * NOTE: may only be called by the agent vault owner.
     * @param _agentVault agent vault address
     */
    function cancelUnderlyingWithdrawal(
        address _agentVault
    )
        external
        notFullyEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        uint64 announcementId = agent.announcedUnderlyingWithdrawalId;
        require(announcementId != 0, NoActiveAnnouncement());
        // clear active withdrawal announcement
        agent.announcedUnderlyingWithdrawalId = 0;
        // send event
        emit IAssetManagerEvents.UnderlyingWithdrawalCancelled(_agentVault, announcementId);
    }
}