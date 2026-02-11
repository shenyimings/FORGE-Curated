// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Conversion} from "./Conversion.sol";
import {AgentCollateral} from "./AgentCollateral.sol";
import {CoreVaultClient} from "./CoreVaultClient.sol";
import {Agent} from "./data/Agent.sol";
import {AgentPayout} from "./AgentPayout.sol";
import {AgentBacking} from "./AgentBacking.sol";
import {Collateral} from "./data/Collateral.sol";
import {Redemption} from "./data/Redemption.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Globals} from "./Globals.sol";

library RedemptionDefaults {
    using SafePct for uint256;
    using Agent for Agent.State;
    using AgentCollateral for Collateral.Data;

    error NotEnoughPoolCollateralToCoverFailedVaultPayment();
    error NotEnoughAgentPoolTokensToCoverFailedVaultPayment();

    function executeDefaultOrCancel(
        Agent.State storage _agent,
        Redemption.Request storage _request,
        uint256 _redemptionRequestId
    )
        internal
    {
        // should only be used for active redemptions (should be checked before)
        assert(_request.status == Redemption.Status.ACTIVE);
        if (!_request.transferToCoreVault) {
            // ordinary redemption default - pay redeemer in one or both collaterals
            (uint256 paidC1Wei, uint256 paidPoolWei) = _collateralAmountForRedemption(_agent, _request);
            (bool successVault,) = AgentPayout.tryPayoutFromVault(_agent, _request.redeemer, paidC1Wei);
            if (!successVault) {
                // agent vault payment has failed - replace with pool payment (but see method comment for conditions)
                paidPoolWei = _replaceFailedVaultPaymentWithPool(_agent, _request, paidC1Wei, paidPoolWei);
                paidC1Wei = 0;
            }
            if (paidPoolWei > 0) {
                AgentPayout.payoutFromPool(_agent, _request.redeemer, paidPoolWei, paidPoolWei);
            }
            // release remaining agent collateral
            AgentBacking.endRedeemingAssets(_agent, _request.valueAMG, _request.poolSelfClose);
            // underlying balance is not added to free balance yet, because we don't know if there was a late payment
            // it will be (or was already) updated in call to confirmRedemptionPayment
            emit IAssetManagerEvents.RedemptionDefault(_agent.vaultAddress(), _request.redeemer, _redemptionRequestId,
                _request.underlyingValueUBA, paidC1Wei, paidPoolWei);
        } else {
            // default can be handled as ordinary default by bots, but nothing is paid out - instead
            // FAssets are re-minted (which can be detected in trackers by TransferToCoreVaultDefaulted event)
            emit IAssetManagerEvents.RedemptionDefault(_agent.vaultAddress(), _request.redeemer, _redemptionRequestId,
                _request.underlyingValueUBA, 0, 0);
            // core vault transfer default - re-create tickets
            CoreVaultClient.cancelTransferToCoreVault(_agent, _request, _redemptionRequestId);
        }
    }

    /**
     * Vault payment has failed, possible reason is that the redeemer address is blacklisted by the
     * stablecoin. This has to be resolved somehow, otherwise the redeemer gets nothing and the agent's
     * collateral stays locked forever. Therefore we pay from the pool, but only if the agent has
     * enough pool tokens to cover the vault payment (plus the required percentage for the remaining
     * backing). We also require that the whole payment does not lower pool CR (possibly triggering liquidation).
     * In this way the pool providers aren't at loss and the agent can always unlock
     * the collateral by buying more collateral pool tokens.
     */
    function _replaceFailedVaultPaymentWithPool(
        Agent.State storage _agent,
        Redemption.Request storage _request,
        uint256 _paidC1Wei,
        uint256 _paidPoolWei
    )
        private view
        returns (uint256)
    {
        Collateral.CombinedData memory cd = AgentCollateral.combinedData(_agent);
        // check that there are enough agent pool tokens
        uint256 poolTokenEquiv = _paidC1Wei
            .mulDiv(cd.agentPoolTokens.amgToTokenWeiPrice, cd.agentCollateral.amgToTokenWeiPrice);
        uint256 requiredPoolTokensForRemainder =
            uint256(_agent.reservedAMG + _agent.mintedAMG + _agent.redeemingAMG - _request.valueAMG)
                .mulDiv(cd.agentPoolTokens.amgToTokenWeiPrice, Conversion.AMG_TOKEN_WEI_PRICE_SCALE)
                .mulBips(Globals.getSettings().mintingPoolHoldingsRequiredBIPS);
        require(requiredPoolTokensForRemainder + poolTokenEquiv <= cd.agentPoolTokens.fullCollateral,
            NotEnoughAgentPoolTokensToCoverFailedVaultPayment());
        // check that pool CR won't be lowered
        uint256 poolWeiEquiv = _paidC1Wei
            .mulDiv(cd.poolCollateral.amgToTokenWeiPrice, cd.agentCollateral.amgToTokenWeiPrice);
        uint256 combinedPaidPoolWei = _paidPoolWei + poolWeiEquiv;
        require(combinedPaidPoolWei <= cd.poolCollateral.maxRedemptionCollateral(_agent, _request.valueAMG),
            NotEnoughPoolCollateralToCoverFailedVaultPayment());
        return combinedPaidPoolWei;
    }

    // payment calculation: pay redemptionDefaultFactorVaultCollateralBIPS (>= 1) from agent vault collateral
    // however, if there is not enough in agent's vault, pay from pool
    // assured: _vaultCollateralWei <= fullCollateralC1, _poolWei <= fullPoolCollateral
    function _collateralAmountForRedemption(
        Agent.State storage _agent,
        Redemption.Request storage _request
    )
        private view
        returns (uint256 _vaultCollateralWei, uint256 _poolWei)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // calculate collateral data for vault collateral
        Collateral.Data memory cdAgent = AgentCollateral.agentVaultCollateralData(_agent);
        uint256 maxVaultCollateralWei = cdAgent.maxRedemptionCollateral(_agent, _request.valueAMG);
        // for pool self close redemption, everything is paid from agent's vault collateral
        if (_request.poolSelfClose) {
            _vaultCollateralWei = Conversion.convertAmgToTokenWei(_request.valueAMG, cdAgent.amgToTokenWeiPrice);
            _poolWei = 0;
            // if there is not enough vault collateral, just reduce the payment
            _vaultCollateralWei = Math.min(_vaultCollateralWei, maxVaultCollateralWei);
        } else {
            _vaultCollateralWei = Conversion.convertAmgToTokenWei(_request.valueAMG, cdAgent.amgToTokenWeiPrice)
                .mulBips(settings.redemptionDefaultFactorVaultCollateralBIPS);
            _poolWei = 0;
            // if there is not enough collateral held by agent, pay from the pool
            if (_vaultCollateralWei > maxVaultCollateralWei) {
                // calculate paid amount and max available amount from the pool
                Collateral.Data memory cdPool = AgentCollateral.poolCollateralData(_agent);
                uint256 maxPoolWei = cdPool.maxRedemptionCollateral(_agent, _request.valueAMG);
                uint256 extraPoolAmg = uint256(_request.valueAMG)
                    .mulDivRoundUp(_vaultCollateralWei - maxVaultCollateralWei, _vaultCollateralWei);
                _vaultCollateralWei = maxVaultCollateralWei;
                _poolWei = Conversion.convertAmgToTokenWei(extraPoolAmg, cdPool.amgToTokenWeiPrice);
                // if there is not enough collateral in the pool, just reduce the payment - however this is not likely,
                // since pool CR is much higher that agent CR
                _poolWei = Math.min(_poolWei, maxPoolWei);
            }
        }
    }
}