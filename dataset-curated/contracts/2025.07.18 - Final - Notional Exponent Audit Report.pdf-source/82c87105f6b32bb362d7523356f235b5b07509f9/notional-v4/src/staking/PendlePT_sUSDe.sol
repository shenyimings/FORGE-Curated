// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "./PendlePT.sol";
import "../withdraws/Ethena.sol";
import "../interfaces/ITradingModule.sol";

contract PendlePT_sUSDe is PendlePT {
    using SafeERC20 for ERC20;

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address asset,
        address yieldToken,
        uint256 feeRate,
        IWithdrawRequestManager withdrawRequestManager
    ) PendlePT(market, tokenInSY, tokenOutSY, asset, yieldToken, feeRate, withdrawRequestManager) {
        require(tokenOutSY == address(sUSDe));
    }

    /// @notice The vast majority of the sUSDe liquidity is in an sDAI/sUSDe curve pool.
    /// sDAI has much greater liquidity once it is unwrapped as DAI so that is done manually
    /// in this method.
    function _executeInstantRedemption(
        uint256 yieldTokensToRedeem,
        bytes memory redeemData
    ) internal override virtual returns (uint256 assetsPurchased) {
        PendleRedeemParams memory params = abi.decode(redeemData, (PendleRedeemParams));
        uint256 netTokenOut = _redeemPT(yieldTokensToRedeem, params.limitOrderData);

        Trade memory sDAITrade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(sUSDe),
            buyToken: address(sDAI),
            amount: netTokenOut,
            limit: 0, // NOTE: no slippage guard is set here, it is enforced in the second leg
                        // of the trade.
            deadline: block.timestamp,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0x167478921b907422F8E88B43C4Af2B8BEa278d3A,
                fromIndex: 1, // sUSDe
                toIndex: 0 // sDAI
            }))
        });

        (/* */, uint256 sDAIAmount) = _executeTrade(sDAITrade, uint16(DexId.CURVE_V2));

        // Unwraps the sDAI to DAI
        uint256 daiAmount = sDAI.redeem(sDAIAmount, address(this), address(this));
        
        if (asset != address(DAI)) {
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: address(DAI),
                buyToken: asset,
                amount: daiAmount,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Trades the unwrapped DAI back to the given token.
            (/* */, assetsPurchased) = _executeTrade(trade, params.dexId);
        } else {
            if (params.minPurchaseAmount > daiAmount) revert SlippageTooHigh(daiAmount, params.minPurchaseAmount);
            assetsPurchased = daiAmount;
        }
    }
}
