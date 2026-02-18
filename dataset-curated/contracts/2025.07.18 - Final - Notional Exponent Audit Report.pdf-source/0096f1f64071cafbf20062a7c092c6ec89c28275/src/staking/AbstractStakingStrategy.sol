// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {WithdrawRequestNotFinalized} from "../interfaces/Errors.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {
    IWithdrawRequestManager,
    WithdrawRequest,
    TokenizedWithdrawRequest
} from "../interfaces/IWithdrawRequestManager.sol";
import {ADDRESS_REGISTRY} from "../utils/Constants.sol";
import {Trade, TradeType, TRADING_MODULE} from "../interfaces/ITradingModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct RedeemParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

struct DepositParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

/**
 * Supports vaults that borrow a token and stake it into a token that earns yield but may
 * require some illiquid redemption period.
 */
abstract contract AbstractStakingStrategy is AbstractYieldStrategy {
    using SafeERC20 for ERC20;

    address internal immutable withdrawToken;

    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        IWithdrawRequestManager _withdrawRequestManager
    ) AbstractYieldStrategy(_asset, _yieldToken, _feeRate, ERC20(_yieldToken).decimals()) {
        // For Pendle PT the yield token does not define the withdraw request manager,
        // it is the token out sy
        withdrawRequestManager = _withdrawRequestManager;
        withdrawToken = address(withdrawRequestManager) != address(0) ? withdrawRequestManager.WITHDRAW_TOKEN() : address(0);
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (t_CurrentAccount != address(0) && _isWithdrawRequestPending(t_CurrentAccount)) {
            (bool hasRequest, uint256 value) = withdrawRequestManager.getWithdrawRequestValue(
                address(this), t_CurrentAccount, asset, shares
            );

            // If the account does not have a withdraw request then this will fall through
            // to the super implementation.
            if (hasRequest) return value;
        }

        return super.convertToAssets(shares);
    }

    function _initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesHeld,
        bytes memory data
    ) internal override virtual returns (uint256 requestId) {
        ERC20(yieldToken).approve(address(withdrawRequestManager), yieldTokenAmount);
        requestId = withdrawRequestManager.initiateWithdraw({
            account: account, yieldTokenAmount: yieldTokenAmount, sharesAmount: sharesHeld, data: data
        });
    }

    /// @dev By default we can use the withdraw request manager to stake the tokens
    function _mintYieldTokens(uint256 assets, address /* receiver */, bytes memory depositData) internal override virtual {
        ERC20(asset).approve(address(withdrawRequestManager), assets);
        withdrawRequestManager.stakeTokens(address(asset), assets, depositData);
    }

    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        bool isEscrowed,
        bytes memory redeemData
    ) internal override {
        if (isEscrowed) {
            (WithdrawRequest memory w, /* */) = withdrawRequestManager.getWithdrawRequest(address(this), sharesOwner);
            uint256 yieldTokensBurned = uint256(w.yieldTokenAmount) * sharesToRedeem / w.sharesAmount;

            (uint256 tokensClaimed, bool finalized) = withdrawRequestManager.finalizeAndRedeemWithdrawRequest({
                account: sharesOwner, withdrawYieldTokenAmount: yieldTokensBurned, sharesToBurn: sharesToRedeem
            });
            if (!finalized) revert WithdrawRequestNotFinalized(w.requestId);

            // Trades may be required here if the borrowed token is not the same as what is
            // received when redeeming.
            if (asset != withdrawToken) {
                RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
                Trade memory trade = Trade({
                    tradeType: TradeType.EXACT_IN_SINGLE,
                    sellToken: address(withdrawToken),
                    buyToken: address(asset),
                    amount: tokensClaimed,
                    limit: params.minPurchaseAmount,
                    deadline: block.timestamp,
                    exchangeData: params.exchangeData
                });

                _executeTrade(trade, params.dexId);
            }
        } else {
            uint256 yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
            _executeInstantRedemption(yieldTokensBurned, redeemData);
        }
    }

    /// @notice Default implementation for an instant redemption is to sell the staking token to the
    /// borrow token through the trading module. Can be overridden if required for different implementations.
    function _executeInstantRedemption(
        uint256 yieldTokensToRedeem,
        bytes memory redeemData
    ) internal virtual returns (uint256 assetsPurchased) {
        RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(yieldToken),
            buyToken: address(asset),
            amount: yieldTokensToRedeem,
            limit: params.minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: params.exchangeData
        });

        // Executes a trade on the given Dex, the vault must have permissions set for
        // each dex and token it wants to sell.
        (/* */, assetsPurchased) = _executeTrade(trade, params.dexId);
    }
    
    function _preLiquidation(address, address, uint256, uint256) internal override { /* no-op */ }

    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal override returns (bool didTokenize) {
        if (address(withdrawRequestManager) != address(0)) {
            // No need to accrue fees because neither the total supply or total yield token balance is changing. If there
            // is no withdraw request then this will be a noop.
            didTokenize = withdrawRequestManager.tokenizeWithdrawRequest(liquidateAccount, liquidator, sharesToLiquidator);
        }
    }

}