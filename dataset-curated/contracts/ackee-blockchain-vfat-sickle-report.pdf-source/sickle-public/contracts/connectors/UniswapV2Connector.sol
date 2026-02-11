// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV2Router02 } from
    "contracts/interfaces/external/uniswap/IUniswapV2Router02.sol";
import { IUniswapV2Pair } from
    "contracts/interfaces/external/uniswap/IUniswapV2Pair.sol";

import {
    ILiquidityConnector,
    AddLiquidityParams,
    RemoveLiquidityParams,
    SwapParams,
    GetAmountOutParams
} from "contracts/interfaces/ILiquidityConnector.sol";

struct UniswapV2SwapExtraData {
    address[] path;
}

contract UniswapV2Connector is ILiquidityConnector {
    function addLiquidity(
        AddLiquidityParams memory addLiquidityParams
    ) external payable override {
        IUniswapV2Router02(addLiquidityParams.router).addLiquidity(
            addLiquidityParams.tokens[0],
            addLiquidityParams.tokens[1],
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
        IUniswapV2Router02(removeLiquidityParams.router).removeLiquidity(
            removeLiquidityParams.tokens[0],
            removeLiquidityParams.tokens[1],
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
        UniswapV2SwapExtraData memory extraData =
            abi.decode(swap.extraData, (UniswapV2SwapExtraData));

        IUniswapV2Router02(swap.router).swapExactTokensForTokens(
            swap.amountIn,
            swap.minAmountOut,
            extraData.path,
            address(this),
            block.timestamp
        );
    }

    function getAmountOut(
        GetAmountOutParams memory getAmountOutParams
    ) external view override returns (uint256) {
        address token0 = IUniswapV2Pair(getAmountOutParams.lpToken).token0();
        (uint256 reserve0, uint256 reserve1,) =
            IUniswapV2Pair(getAmountOutParams.lpToken).getReserves();
        if (getAmountOutParams.tokenIn == token0) {
            return IUniswapV2Router02(getAmountOutParams.router).getAmountOut(
                getAmountOutParams.amountIn, reserve0, reserve1
            );
        } else {
            return IUniswapV2Router02(getAmountOutParams.router).getAmountOut(
                getAmountOutParams.amountIn, reserve1, reserve0
            );
        }
    }
}
