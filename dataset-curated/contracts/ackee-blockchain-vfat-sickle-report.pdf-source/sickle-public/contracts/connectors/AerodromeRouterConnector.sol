// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IRouter } from "contracts/interfaces/external/aerodrome/IRouter.sol";
import { IPool } from "contracts/interfaces/external/aerodrome/IPool.sol";

import {
    ILiquidityConnector,
    AddLiquidityParams,
    RemoveLiquidityParams,
    SwapParams,
    GetAmountOutParams
} from "contracts/interfaces/ILiquidityConnector.sol";

struct AerodromeLiquidityExtraData {
    bool isStablePool;
}

struct AerodromeSwapExtraData {
    IRouter.Route[] routes;
}

contract AerodromeRouterConnector is ILiquidityConnector {
    function addLiquidity(
        AddLiquidityParams memory addLiquidityParams
    ) external payable override {
        AerodromeLiquidityExtraData memory _extraData = abi.decode(
            addLiquidityParams.extraData, (AerodromeLiquidityExtraData)
        );
        IRouter(addLiquidityParams.router).addLiquidity(
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
        AerodromeLiquidityExtraData memory _extraData = abi.decode(
            removeLiquidityParams.extraData, (AerodromeLiquidityExtraData)
        );
        IRouter(removeLiquidityParams.router).removeLiquidity(
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
        AerodromeSwapExtraData memory _extraData =
            abi.decode(swap.extraData, (AerodromeSwapExtraData));
        IRouter(swap.router).swapExactTokensForTokens(
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
        return IPool(getAmountOutParams.lpToken).getAmountOut(
            getAmountOutParams.amountIn, getAmountOutParams.tokenIn
        );
    }
}
