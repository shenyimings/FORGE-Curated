// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IReferencedPaymentNonexistence, IConfirmedBlockHeightExists}
    from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {RedemptionDefaults} from "../library/RedemptionDefaults.sol";
import {Redemptions} from "../library/Redemptions.sol";
import {TransactionAttestation} from "../library/TransactionAttestation.sol";
import {Agent} from "../library/data/Agent.sol";
import {Agents} from "../library/Agents.sol";
import {AgentPayout} from "../library/AgentPayout.sol";
import {Redemption} from "../library/data/Redemption.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {PaymentReference} from "../library/data/PaymentReference.sol";
import {Globals} from "../library/Globals.sol";


contract RedemptionDefaultsFacet is AssetManagerBase, ReentrancyGuard {
    using SafeCast for uint256;

    error ShouldDefaultFirst();
    error OnlyRedeemerExecutorOrAgent();
    error RedemptionNonPaymentProofWindowTooShort();
    error RedemptionDefaultTooEarly();
    error RedemptionNonPaymentMismatch();
    error InvalidRedemptionStatus();
    error SourceAddressesNotSupported();

    /**
     * If the agent doesn't transfer the redeemed underlying assets in time (until the last allowed block on
     * the underlying chain), the redeemer calls this method and receives payment in collateral (with some extra).
     * The agent can also call default if the redeemer is unresponsive, to payout the redeemer and free the
     * remaining collateral.
     * NOTE: The attestation request must be done with `checkSourceAddresses=false`.
     * NOTE: may only be called by the redeemer (= creator of the redemption request),
     *   the executor appointed by the redeemer,
     *   or the agent owner (= owner of the agent vault in the redemption request)
     * @param _proof proof that the agent didn't pay with correct payment reference on the underlying chain
     * @param _redemptionRequestId id of an existing redemption request
     */
    function redemptionPaymentDefault(
        IReferencedPaymentNonexistence.Proof calldata _proof,
        uint256 _redemptionRequestId
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        require(!_proof.data.requestBody.checkSourceAddresses, SourceAddressesNotSupported());
        Redemption.Request storage request = Redemptions.getRedemptionRequest(_redemptionRequestId, true);
        Agent.State storage agent = Agent.get(request.agentVault);
        require(request.status == Redemption.Status.ACTIVE, InvalidRedemptionStatus());
        // verify transaction
        TransactionAttestation.verifyReferencedPaymentNonexistence(_proof);
        // check non-payment proof
        require(_proof.data.requestBody.standardPaymentReference ==
                PaymentReference.redemption(_redemptionRequestId) &&
            _proof.data.requestBody.destinationAddressHash == request.redeemerUnderlyingAddressHash &&
            _proof.data.requestBody.amount == request.underlyingValueUBA - request.underlyingFeeUBA,
            RedemptionNonPaymentMismatch());
        require(_proof.data.responseBody.firstOverflowBlockNumber > request.lastUnderlyingBlock &&
            _proof.data.responseBody.firstOverflowBlockTimestamp > request.lastUnderlyingTimestamp,
            RedemptionDefaultTooEarly());
        require(_proof.data.requestBody.minimalBlockNumber <= request.firstUnderlyingBlock,
            RedemptionNonPaymentProofWindowTooShort());
        // We allow only redeemers or agents to trigger redemption default, since they may want
        // to do it at some particular time. (Agent might want to call default to unstick redemption when
        // the redeemer is unresponsive.)
        // The exception is transfer to core vault, where anybody can call default after enough time.
        bool expectedSender = msg.sender == request.redeemer || msg.sender == request.executor ||
            Agents.isOwner(agent, msg.sender);
        require(expectedSender || _othersCanConfirmDefault(request), OnlyRedeemerExecutorOrAgent());
        // pay redeemer in collateral / cancel transfer to core vault
        RedemptionDefaults.executeDefaultOrCancel(agent, request, _redemptionRequestId);
        // in case of confirmation by other for core vault transfer, pay the reward
        if (!expectedSender) {
            AgentPayout.payForConfirmationByOthers(agent, msg.sender);
        }
        // pay the executor if the executor called this
        // guarded against reentrancy in RedemptionDefaultsFacet
        Redemptions.payOrBurnExecutorFee(request);
        // don't finish redemption request at end - the agent might still confirm failed payment
        request.status = Redemption.Status.DEFAULTED;
    }

    /**
     * If the agent hasn't performed the payment, the agent can close the redemption request to free underlying funds.
     * This method can trigger the default payment without proof, but only after enough time has passed so that
     * attestation proof of non-payment is not available any more.
     * NOTE: may only be called by the owner of the agent vault in the redemption request.
     * @param _proof proof that the attestation query window can not not contain
     *      the payment/non-payment proof anymore
     * @param _redemptionRequestId id of an existing, but already defaulted, redemption request
     */
    function finishRedemptionWithoutPayment(
        IConfirmedBlockHeightExists.Proof calldata _proof,
        uint256 _redemptionRequestId
    )
        external
        notFullyEmergencyPaused
        nonReentrant
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        Redemption.Request storage request = Redemptions.getRedemptionRequest(_redemptionRequestId, true);
        Agent.State storage agent = Agent.get(request.agentVault);
        Agents.requireAgentVaultOwner(agent);
        // the request should have been defaulted by providing a non-payment proof to redemptionPaymentDefault(),
        // except in very rare case when both agent and redeemer cannot perform confirmation while the attestation
        // is still available (~ 1 day) - in this case the agent can perform default without proof
        if (request.status == Redemption.Status.ACTIVE) {
            // verify proof
            TransactionAttestation.verifyConfirmedBlockHeightExists(_proof);
            // if non-payment proof is still available, should use redemptionPaymentDefault() instead
            // (the last inequality tests that the query window in proof is at least as big as configured)
            require(_proof.data.responseBody.lowestQueryWindowBlockNumber > request.lastUnderlyingBlock
                && _proof.data.responseBody.lowestQueryWindowBlockTimestamp > request.lastUnderlyingTimestamp
                && _proof.data.responseBody.lowestQueryWindowBlockTimestamp + settings.attestationWindowSeconds <=
                    _proof.data.responseBody.blockTimestamp,
                ShouldDefaultFirst());
            RedemptionDefaults.executeDefaultOrCancel(agent, request, _redemptionRequestId);
            // burn the executor fee
            // guarded against reentrancy in RedemptionDefaultsFacet
            Redemptions.burnExecutorFee(request);
            // make sure it cannot be defaulted again
            request.status = Redemption.Status.DEFAULTED;
        }
        // we do not finish redemption request here, because we cannot be certain that proofs have expired,
        // so finishing the request could lead to successful challenge of the agent that paid, but the proof expired
    }

    function _othersCanConfirmDefault(
        Redemption.Request storage _request
    )
        private view
        returns (bool)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // others can confirm default only for core vault transfers and only after enough time
        return _request.transferToCoreVault &&
            block.timestamp > _request.timestamp + settings.confirmationByOthersAfterSeconds;
    }
}