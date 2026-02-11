// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBalanceDecreasingTransaction} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {AgentCollateral} from "../library/AgentCollateral.sol";
import {Agents} from "../library/Agents.sol";
import {AgentPayout} from "../library/AgentPayout.sol";
import {Conversion} from "../library/Conversion.sol";
import {Globals} from "../library/Globals.sol";
import {Liquidation} from "../library/Liquidation.sol";
import {Redemptions} from "../library/Redemptions.sol";
import {TransactionAttestation} from "../library/TransactionAttestation.sol";
import {UnderlyingBalance} from "../library/UnderlyingBalance.sol";
import {Agent} from "../library/data/Agent.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {Collateral} from "../library/data/Collateral.sol";
import {PaymentConfirmations} from "../library/data/PaymentConfirmations.sol";
import {PaymentReference} from "../library/data/PaymentReference.sol";
import {Redemption} from "../library/data/Redemption.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {SafePct} from "../../utils/library/SafePct.sol";


contract ChallengesFacet is AssetManagerBase, ReentrancyGuard {
    using SafeCast for uint256;
    using SafePct for uint256;
    using PaymentConfirmations for PaymentConfirmations.State;

    error ChallengeNotAgentsAddress();
    error ChallengeAlreadyLiquidating();
    error ChallengeInvalidAgentStatus();
    error ChallengeNotDuplicate();
    error ChallengeTransactionAlreadyConfirmed();
    error ChallengeSameTransactionRepeated();
    error MatchingAnnouncedPaymentActive();
    error MatchingRedemptionActive();
    error MultiplePaymentsChallengeEnoughBalance();

    /**
     * Called with a proof of payment made from agent's underlying address, for which
     * no valid payment reference exists (valid payment references are from redemption and
     * underlying withdrawal announcement calls).
     * On success, immediately triggers full agent liquidation and rewards the caller.
     * @param _payment proof of a transaction from the agent's underlying address
     * @param _agentVault agent vault address
     */
    function illegalPaymentChallenge(
        IBalanceDecreasingTransaction.Proof calldata _payment,
        address _agentVault
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        Agent.State storage agent = Agent.get(_agentVault);
        _validateAgentStatus(agent);
        // verify transaction
        TransactionAttestation.verifyBalanceDecreasingTransaction(_payment);
        // check the payment originates from agent's address
        require(_payment.data.responseBody.sourceAddressHash == agent.underlyingAddressHash,
            ChallengeNotAgentsAddress());
        // check that proof of this tx wasn't used before - otherwise we could
        // trigger liquidation for already proved redemption payments
        require(!state.paymentConfirmations.transactionConfirmed(_payment), ChallengeTransactionAlreadyConfirmed());
        // check that payment reference is invalid (paymentReference == 0 is always invalid payment)
        bytes32 paymentReference = _payment.data.responseBody.standardPaymentReference;
        if (paymentReference != 0) {
            if (PaymentReference.isValid(paymentReference, PaymentReference.REDEMPTION)) {
                uint256 redemptionId = PaymentReference.decodeId(paymentReference);
                Redemption.Request storage redemption = state.redemptionRequests[redemptionId];
                // Redemption must be for the correct agent, must not be rejected and
                // only statuses ACTIVE and DEFAULTED mean that redemption is still missing a payment proof.
                // Payments must not be made before the current underlying block when redemption was requested.
                // We do not check that the payment is not too late, because on UTXO chains legal payments can be
                // delayed by arbitrary time due to high fees and cannot be canceled, which could lead to
                // unnecessary full liquidations.
                bool redemptionActive = redemption.agentVault == _agentVault
                    && Redemptions.isOpen(redemption)
                    && _payment.data.responseBody.blockNumber >= redemption.firstUnderlyingBlock;
                require(!redemptionActive, MatchingRedemptionActive());
            }
            if (PaymentReference.isValid(paymentReference, PaymentReference.ANNOUNCED_WITHDRAWAL)) {
                uint256 announcementId = PaymentReference.decodeId(paymentReference);
                // valid announced withdrawal cannot have announcementId == 0 and must match the agent's announced id
                // but PaymentReference.isValid already checks that id in the reference != 0, so no extra check needed
                require(announcementId != agent.announcedUnderlyingWithdrawalId, MatchingAnnouncedPaymentActive());
            }
        }
        // start liquidation and reward challengers
        _liquidateAndRewardChallenger(agent, msg.sender, agent.mintedAMG);
        // emit events
        emit IAssetManagerEvents.IllegalPaymentConfirmed(_agentVault, _payment.data.requestBody.transactionId);
    }

    /**
     * Called with proofs of two payments made from agent's underlying address
     * with the same payment reference (each payment reference is valid for only one payment).
     * On success, immediately triggers full agent liquidation and rewards the caller.
     * @param _payment1 proof of first payment from the agent's underlying address
     * @param _payment2 proof of second payment from the agent's underlying address
     * @param _agentVault agent vault address
     */
    function doublePaymentChallenge(
        IBalanceDecreasingTransaction.Proof calldata _payment1,
        IBalanceDecreasingTransaction.Proof calldata _payment2,
        address _agentVault
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        Agent.State storage agent = Agent.get(_agentVault);
        _validateAgentStatus(agent);
        // verify transactions
        TransactionAttestation.verifyBalanceDecreasingTransaction(_payment1);
        TransactionAttestation.verifyBalanceDecreasingTransaction(_payment2);
        // check the payments are unique and originate from agent's address
        require(_payment1.data.requestBody.transactionId != _payment2.data.requestBody.transactionId,
            ChallengeSameTransactionRepeated());
        require(_payment1.data.responseBody.sourceAddressHash == agent.underlyingAddressHash,
            ChallengeNotAgentsAddress());
        require(_payment2.data.responseBody.sourceAddressHash == agent.underlyingAddressHash,
            ChallengeNotAgentsAddress());
        // payment references must be equal
        require(_payment1.data.responseBody.standardPaymentReference ==
            _payment2.data.responseBody.standardPaymentReference, ChallengeNotDuplicate());
        // ! no need to check that transaction wasn't confirmed - this is always illegal
        // start liquidation and reward challengers
        _liquidateAndRewardChallenger(agent, msg.sender, agent.mintedAMG);
        // emit events
        emit IAssetManagerEvents.DuplicatePaymentConfirmed(_agentVault, _payment1.data.requestBody.transactionId,
            _payment2.data.requestBody.transactionId);
    }

    /**
     * Called with proofs of several (otherwise legal) payments, which together make agent's
     * underlying free balance negative (i.e. the underlying address balance is less than
     * the total amount of backed f-assets).
     * On success, immediately triggers full agent liquidation and rewards the caller.
     * @param _payments proofs of several distinct payments from the agent's underlying address
     * @param _agentVault agent vault address
     */
    function freeBalanceNegativeChallenge(
        IBalanceDecreasingTransaction.Proof[] calldata _payments,
        address _agentVault
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        Agent.State storage agent = Agent.get(_agentVault);
        _validateAgentStatus(agent);
        // check the payments originates from agent's address, are not confirmed already and calculate total
        int256 total = 0;
        for (uint256 i = 0; i < _payments.length; i++) {
            IBalanceDecreasingTransaction.Proof calldata pmi = _payments[i];
            TransactionAttestation.verifyBalanceDecreasingTransaction(pmi);
            // check there are no duplicate transactions
            for (uint256 j = 0; j < i; j++) {
                require(_payments[j].data.requestBody.transactionId != pmi.data.requestBody.transactionId,
                    ChallengeSameTransactionRepeated());
            }
            require(pmi.data.responseBody.sourceAddressHash == agent.underlyingAddressHash,
                ChallengeNotAgentsAddress());
            if (state.paymentConfirmations.transactionConfirmed(pmi)) {
                continue;   // ignore payments that have already been confirmed
            }
            bytes32 paymentReference = pmi.data.responseBody.standardPaymentReference;
            if (PaymentReference.isValid(paymentReference, PaymentReference.REDEMPTION)) {
                // for open redemption, we don't count the value that should be paid to free balance deduction.
                // Note that we don't need to check that the redemption is for this agent, because payments
                // with redemption reference for other agent can be immediatelly challenged as illegal.
                uint256 redemptionId = PaymentReference.decodeId(pmi.data.responseBody.standardPaymentReference);
                Redemption.Request storage request = state.redemptionRequests[redemptionId];
                uint256 redemptionValue = Redemptions.isOpen(request) ? request.underlyingValueUBA : 0;
                total += pmi.data.responseBody.spentAmount - SafeCast.toInt256(redemptionValue);
            } else {
                // for other payment types (announced withdrawal), everything is paid from free balance
                total += pmi.data.responseBody.spentAmount;
            }
        }
        // check that total spent free balance is more than actual free underlying balance
        int256 balanceAfterPayments = agent.underlyingBalanceUBA - total;
        uint256 requiredBalance = UnderlyingBalance.requiredUnderlyingUBA(agent);
        require(balanceAfterPayments < requiredBalance.toInt256(), MultiplePaymentsChallengeEnoughBalance());
        // start liquidation and reward challengers
        _liquidateAndRewardChallenger(agent, msg.sender, agent.mintedAMG);
        // emit events
        emit IAssetManagerEvents.UnderlyingBalanceTooLow(_agentVault, balanceAfterPayments, requiredBalance);
    }

    function _validateAgentStatus(Agent.State storage _agent)
        private view
    {
        // If the agent is already being fully liquidated, no need for more challenges; this also prevents
        // double challenges.
        Agent.Status status = _agent.status;
        require(status != Agent.Status.FULL_LIQUIDATION, ChallengeAlreadyLiquidating());
        // For agents in status destroying, the challenges are pointless (but would still reward the
        // challenger, so they are better forbidden).
        require(status != Agent.Status.DESTROYING, ChallengeInvalidAgentStatus());
    }

    function _liquidateAndRewardChallenger(
        Agent.State storage _agent,
        address _challenger,
        uint256 _backingAMGAtChallenge
    )
        private
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // start full liquidation
        Liquidation.startFullLiquidation(_agent);
        // calculate the reward
        Collateral.Data memory collateralData =
            AgentCollateral.agentVaultCollateralData(_agent);
        uint256 rewardAMG = _backingAMGAtChallenge.mulBips(settings.paymentChallengeRewardBIPS);
        uint256 rewardC1Wei = Conversion.convertAmgToTokenWei(rewardAMG, collateralData.amgToTokenWeiPrice)
            + Agents.convertUSD5ToVaultCollateralWei(_agent, settings.paymentChallengeRewardUSD5);
        AgentPayout.payoutFromVault(_agent, _challenger, rewardC1Wei);
    }
}