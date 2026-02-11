// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-core/interfaces/callback/IUniswapV3FlashCallback.sol";

import "../interfaces/IVault.sol";
import "./Swapper.sol";

/// @title Helper contract which allows atomic liquidation and needed swaps by using UniV3 Flashloan
contract FlashloanLiquidator is Swapper, IUniswapV3FlashCallback {
    struct FlashCallbackData {
        uint256 tokenId;
        uint256 liquidationCost;
        IVault vault;
        IERC20 asset;
        RouterSwapParams swap0;
        RouterSwapParams swap1;
        address liquidator;
        uint256 minReward;
        uint256 deadline;
    }

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        address _universalRouter,
        address _zeroxAllowanceHolder
    )
        Swapper(_nonfungiblePositionManager, _universalRouter, _zeroxAllowanceHolder)
    {}

    struct LiquidateParams {
        uint256 tokenId; // loan to liquidate
        IVault vault; // vault where the loan is
        IUniswapV3Pool flashLoanPool; // pool which is used for flashloan - may not be used in the swaps below
        uint256 amount0In; // how much of token0 to swap to asset (0 if no swap should be done)
        bytes swapData0; // swap data for token0 swap
        uint256 amount1In; // how much of token1 to swap to asset (0 if no swap should be done)
        bytes swapData1; // swap data for token1 swap
        uint256 minReward; // min reward amount (works as a global slippage control for complete operation)
        uint256 deadline; // deadline for uniswap operations
    }

    /// @notice Liquidates a loan, using a Uniswap Flashloan
    function liquidate(LiquidateParams calldata params) external {
        (,,, uint256 liquidationCost, uint256 liquidationValue) = params.vault.loanInfo(params.tokenId);
        if (liquidationValue == 0) {
            revert NotLiquidatable();
        }

        (,, address token0, address token1,,,,,,,,) = nonfungiblePositionManager.positions(params.tokenId);
        address asset = params.vault.asset();

        bool isAsset0 = params.flashLoanPool.token0() == asset;
        bytes memory data = abi.encode(
            FlashCallbackData(
                params.tokenId,
                liquidationCost,
                params.vault,
                IERC20(asset),
                RouterSwapParams(IERC20(token0), IERC20(asset), params.amount0In, 0, params.swapData0),
                RouterSwapParams(IERC20(token1), IERC20(asset), params.amount1In, 0, params.swapData1),
                msg.sender,
                params.minReward,
                params.deadline
            )
        );
        params.flashLoanPool.flash(address(this), isAsset0 ? liquidationCost : 0, !isAsset0 ? liquidationCost : 0, data);
    }

    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata callbackData) external override {
        // no origin check is needed - because the contract doesn't hold any funds - there is no benefit in calling uniswapV3FlashCallback() from another context

        FlashCallbackData memory data = abi.decode(callbackData, (FlashCallbackData));

        SafeERC20.safeIncreaseAllowance(data.asset, address(data.vault), data.liquidationCost);
        data.vault.liquidate(
            IVault.LiquidateParams(
                data.tokenId, data.swap0.amountIn, data.swap1.amountIn, address(this), "", data.deadline
            )
        );
        SafeERC20.safeApprove(data.asset, address(data.vault), 0);

        // do swaps
        _routerSwap(data.swap0);
        _routerSwap(data.swap1);

        // transfer lent amount + fee (only one token can have fee) - back to pool
        SafeERC20.safeTransfer(data.asset, msg.sender, data.liquidationCost + (fee0 + fee1));

        uint256 balance;

        // return all leftover tokens to liquidator
        if (data.swap0.tokenIn != data.asset) {
            balance = data.swap0.tokenIn.balanceOf(address(this));
            if (balance != 0) {
                SafeERC20.safeTransfer(data.swap0.tokenIn, data.liquidator, balance);
            }
        }
        if (data.swap1.tokenIn != data.asset) {
            balance = data.swap1.tokenIn.balanceOf(address(this));
            if (balance != 0) {
                SafeERC20.safeTransfer(data.swap1.tokenIn, data.liquidator, balance);
            }
        }
        {
            balance = data.asset.balanceOf(address(this));
            if (balance < data.minReward) {
                revert NotEnoughReward();
            }
            if (balance != 0) {
                SafeERC20.safeTransfer(data.asset, data.liquidator, balance);
            }
        }
    }
}
