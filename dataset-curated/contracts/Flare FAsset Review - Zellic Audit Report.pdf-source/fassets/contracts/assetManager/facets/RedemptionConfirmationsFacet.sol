// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPayment} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Redemptions} from "../library/Redemptions.sol";
import {RedemptionDefaults} from "../library/RedemptionDefaults.sol";
import {Liquidation} from "../library/Liquidation.sol";
import {UnderlyingBalance} from "../library/UnderlyingBalance.sol";
import {CoreVaultClient} from "../library/CoreVaultClient.sol";
import {Agent} from "../library/data/Agent.sol";
import {PaymentConfirmations} from "../library/data/PaymentConfirmations.sol";
import {Redemption} from "../library/data/Redemption.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Globals} from "../library/Globals.sol";
import {TransactionAttestation} from "../library/TransactionAttestation.sol";
import {Agents} from "../library/Agents.sol";
import {AgentBacking} from "../library/AgentBacking.sol";
import {AgentPayout} from "../library/AgentPayout.sol";
import {Conversion} from "../library/Conversion.sol";
import {PaymentReference} from "../library/data/PaymentReference.sol";
import {UnderlyingBlockUpdater} from "../library/UnderlyingBlockUpdater.sol";


contract RedemptionConfirmationsFacet is AssetManagerBase, ReentrancyGuard {
    using SafeCast for uint256;
    using SafePct for uint256;
    using Agent for Agent.State;
    using PaymentConfirmations for PaymentConfirmations.State;

    error InvalidReceivingAddressSelected();
    error SourceNotAgentsUnderlyingAddress();
    error RedemptionPaymentTooOld();
    error InvalidRedemptionReference();

    /**
     * After paying to the redeemer, the agent must call this method to unlock the collateral
     * and to make sure that the redeemer cannot demand payment in collateral on timeout.
     * The same method must be called for any payment status (SUCCESS, FAILED, BLOCKED).
     * In case of FAILED, it just releases agent's underlying funds and the redeemer gets paid in collateral
     * after calling redemptionPaymentDefault.
     * In case of SUCCESS or BLOCKED, remaining underlying funds and collateral are released to the agent.
     * If the agent doesn't confirm payment in enough time (several hours, setting confirmationByOthersAfterSeconds),
     * anybody can do it and get rewarded from agent's vault.
     * NOTE: may only be called by the owner of the agent vault in the redemption request
     *   except if enough time has passed without confirmation - then it can be called by anybody
     * @param _payment proof of the underlying payment (must contain exact `value - fee` amount and correct
     *      payment reference)
     * @param _redemptionRequestId id of an existing redemption request
     */
    function confirmRedemptionPayment(
        IPayment.Proof calldata _payment,
        uint256 _redemptionRequestId
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        Redemption.Request storage request = Redemptions.getRedemptionRequest(_redemptionRequestId, true);
        Agent.State storage agent = Agent.get(request.agentVault);
        // Usually, we require the agent to trigger confirmation.
        // But if the agent doesn't respond for long enough,
        // we allow anybody and that user gets rewarded from agent's vault.
        bool isAgent = Agents.isOwner(agent, msg.sender);
        require(isAgent || _othersCanConfirmPayment(request), Agents.OnlyAgentVaultOwner());
        // verify transaction
        TransactionAttestation.verifyPayment(_payment);
        // payment reference must match
        require(_payment.data.responseBody.standardPaymentReference ==
                PaymentReference.redemption(_redemptionRequestId),
                InvalidRedemptionReference());
        // we do not allow payments before the underlying block at requests, because the payer should have guessed
        // the payment reference, which is good for nothing except attack attempts
        require(_payment.data.responseBody.blockNumber >= request.firstUnderlyingBlock,
            RedemptionPaymentTooOld());
        // Agent's underlying address must be the selected source address. On utxo chains other addresses can also
        // be used for payment, but the spentAmount must be for agent's underlying address.
        require(_payment.data.responseBody.sourceAddressHash == agent.underlyingAddressHash,
            SourceNotAgentsUnderlyingAddress());
        // On UTXO chains, malicious submitter could select agent's return address as receiving address index in FDC
        // request, which would wrongly mark payment as FAILED because the receiver is not the redeemer.
        // Following check prevents this for common payments with single receiver while still allowing payments to
        // actually wrong address to be marked as invalid.
        require(_payment.data.responseBody.intendedReceivingAddressHash != agent.underlyingAddressHash,
            InvalidReceivingAddressSelected());
        // Valid payments are to correct destination, in time, and must have value at least the request payment value.
        (bool paymentValid, string memory failureReason) = _validatePayment(request, _payment);
        Redemption.Status finalStatus;
        if (paymentValid) {
            assert(request.status == Redemption.Status.ACTIVE); // checked in _validatePayment that is not DEFAULTED
            // release agent collateral
            AgentBacking.endRedeemingAssets(agent, request.valueAMG, request.poolSelfClose);
            // mark and notify
            if (_payment.data.responseBody.status == TransactionAttestation.PAYMENT_SUCCESS) {
                finalStatus = Redemption.Status.SUCCESSFUL;
                emit IAssetManagerEvents.RedemptionPerformed(request.agentVault, request.redeemer,
                    _redemptionRequestId, _payment.data.requestBody.transactionId, request.underlyingValueUBA,
                    _payment.data.responseBody.spentAmount);
                if (request.transferToCoreVault) {
                    CoreVaultClient.confirmTransferToCoreVault(_payment, agent, _redemptionRequestId);
                }
            } else {
                assert(_payment.data.responseBody.status == TransactionAttestation.PAYMENT_BLOCKED);
                finalStatus = Redemption.Status.BLOCKED;
                emit IAssetManagerEvents.RedemptionPaymentBlocked(request.agentVault, request.redeemer,
                    _redemptionRequestId, _payment.data.requestBody.transactionId, request.underlyingValueUBA,
                    _payment.data.responseBody.spentAmount);
            }
            // charge the redemption pool fee share by re-minting some fassets
            _mintPoolFee(agent, request, _redemptionRequestId);
        } else {
            finalStatus = Redemption.Status.FAILED;
            // We do not allow retrying failed payments, so just default or cancel here if not defaulted already.
            if (request.status == Redemption.Status.ACTIVE) {
                RedemptionDefaults.executeDefaultOrCancel(agent, request, _redemptionRequestId);
            }
            // notify
            emit IAssetManagerEvents.RedemptionPaymentFailed(request.agentVault, request.redeemer,
                _redemptionRequestId, _payment.data.requestBody.transactionId,
                _payment.data.responseBody.spentAmount, failureReason);
        }
        // agent has finished with redemption - account for used underlying balance and free the remainder
        UnderlyingBalance.updateBalance(agent, -_payment.data.responseBody.spentAmount);
        // record source decreasing transaction so that it cannot be challenged
        AssetManagerState.State storage state = AssetManagerState.get();
        state.paymentConfirmations.confirmSourceDecreasingTransaction(_payment);
        // if the confirmation was done by someone else than agent, pay some reward from agent's vault
        if (!isAgent) {
            AgentPayout.payForConfirmationByOthers(agent, msg.sender);
        }
        // burn executor fee - if confirmed by "other" (also executor), it is already paid from agent's vault
        // guarded against reentrancy in RedemptionConfirmationsFacet
        Redemptions.burnExecutorFee(request);
        // redemption can make agent healthy, so check and pull out of liquidation
        Liquidation.endLiquidationIfHealthy(agent);
        // update underlying block
        UnderlyingBlockUpdater.updateCurrentBlockForVerifiedPayment(_payment);
        // finish
        Redemptions.finishRedemptionRequest(_redemptionRequestId, request, finalStatus);
    }

    function _mintPoolFee(
        Agent.State storage _agent,
        Redemption.Request storage _request,
        uint256 _redemptionRequestId
    )
        private
    {
        uint256 poolFeeUBA = uint256(_request.underlyingFeeUBA).mulBips(_request.poolFeeShareBIPS);
        poolFeeUBA = Conversion.roundUBAToAmg(poolFeeUBA);
        if (poolFeeUBA > 0) {
            AgentBacking.createNewMinting(_agent, Conversion.convertUBAToAmg(poolFeeUBA));
            Globals.getFAsset().mint(address(_agent.collateralPool), poolFeeUBA);
            _agent.collateralPool.fAssetFeeDeposited(poolFeeUBA);
            emit IAssetManagerEvents.RedemptionPoolFeeMinted(_agent.vaultAddress(), _redemptionRequestId, poolFeeUBA);
        }
    }

    function _othersCanConfirmPayment(
        Redemption.Request storage _request
    )
        private view
        returns (bool)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // others can confirm payments only after several hours
        return block.timestamp > _request.timestamp + settings.confirmationByOthersAfterSeconds;
    }

    function _validatePayment(
        Redemption.Request storage request,
        IPayment.Proof calldata _payment
    )
        private view
        returns (bool _paymentValid, string memory _failureReason)
    {
        uint256 paymentValueUBA = uint256(request.underlyingValueUBA) - request.underlyingFeeUBA;
        if (_payment.data.responseBody.status == TransactionAttestation.PAYMENT_FAILED) {
            return (false, "transaction failed");
        } else if (_payment.data.responseBody.intendedReceivingAddressHash != request.redeemerUnderlyingAddressHash) {
            return (false, "not redeemer's address");
        } else if (_payment.data.responseBody.receivedAmount < int256(paymentValueUBA)) { // paymentValueUBA < 2**128
            // for blocked payments, receivedAmount == 0, but it's still receiver's fault
            if (_payment.data.responseBody.status != TransactionAttestation.PAYMENT_BLOCKED) {
                return (false, "redemption payment too small");
            }
        } else if (!request.transferToCoreVault &&
            _payment.data.responseBody.blockNumber > request.lastUnderlyingBlock &&
            _payment.data.responseBody.blockTimestamp > request.lastUnderlyingTimestamp) {
            return (false, "redemption payment too late");
        } else if (request.status == Redemption.Status.DEFAULTED) {
            // Redemption is already defaulted, although the payment was not too late.
            // This indicates a problem in FDC, which gives proofs of both valid payment and nonpayment,
            // but we cannot solve it here. So we just return as failed and the off-chain code should alert.
            return (false, "redemption already defaulted");
        }
        return (true, "");
    }
}