// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    ILiquidityConnector,
    AddLiquidityParams,
    RemoveLiquidityParams,
    SwapParams,
    GetAmountOutParams
} from "contracts/interfaces/ILiquidityConnector.sol";
import { IEqualizerRouter } from
    "contracts/interfaces/external/equalizer/IEqualizerRouter.sol";
import { IPool } from "contracts/interfaces/external/aerodrome/IPool.sol";

struct EqualizerLiquidityExtraData {
    bool isStablePool;
}

struct EqualizerSwapExtraData {
    IEqualizerRouter.Route[] routes;
}

contract EqualizerRouterConnector is ILiquidityConnector {
    function addLiquidity(
        AddLiquidityParams memory addLiquidityParams
    ) external payable override {
        EqualizerLiquidityExtraData memory _extraData = abi.decode(
            addLiquidityParams.extraData, (EqualizerLiquidityExtraData)
        );
        IEqualizerRouter(addLiquidityParams.router).addLiquidity(
            addLiquidityParams.tokens[0],
            addLiquidityParams.tokens[1],
            _extraData.isStablePool,
            addLiquidityParams.desiredAmounts[0],
            addLiquidityParams.desiredAmounts[1],
            addLiquidityParams.minAmounts[0],
            addLiquidityParams.minAmounts[1],
            address(this),
            block.timestamp
        );
    }

    function removeLiquidity(
        RemoveLiquidityParams memory removeLiquidityParams
    ) external override {
        EqualizerLiquidityExtraData memory _extraData = abi.decode(
            removeLiquidityParams.extraData, (EqualizerLiquidityExtraData)
        );
        IEqualizerRouter(removeLiquidityParams.router).removeLiquidity(
            removeLiquidityParams.tokens[0],
            removeLiquidityParams.tokens[1],
            _extraData.isStablePool,
            removeLiquidityParams.lpAmountIn,
            removeLiquidityParams.minAmountsOut[0],
            removeLiquidityParams.minAmountsOut[1],
            address(this),
            block.timestamp
        );
    }

    function swapExactTokensForTokens(
        SwapParams memory swap
    ) external payable override {
        EqualizerSwapExtraData memory _extraData =
            abi.decode(swap.extraData, (EqualizerSwapExtraData));
        IEqualizerRouter(swap.router).swapExactTokensForTokens(
            swap.amountIn,
            swap.minAmountOut,
            _extraData.routes,
            address(this),
            block.timestamp
        );
    }

    function getAmountOut(
        GetAmountOutParams memory getAmountOutParams
    ) external view override returns (uint256) {
        return IPool(getAmountOutParams.router).getAmountOut(
            getAmountOutParams.amountIn, getAmountOutParams.tokenIn
        );
    }
}
