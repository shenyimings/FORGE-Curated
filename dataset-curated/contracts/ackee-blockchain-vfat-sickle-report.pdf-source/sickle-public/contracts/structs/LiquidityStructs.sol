// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AddLiquidityParams {
    address router;
    address lpToken;
    address[] tokens;
    uint256[] desiredAmounts;
    uint256[] minAmounts;
    bytes extraData;
}

struct RemoveLiquidityParams {
    address router;
    address lpToken;
    address[] tokens;
    uint256 lpAmountIn;
    uint256[] minAmountsOut;
    bytes extraData;
}

struct SwapParams {
    address router;
    uint256 amountIn;
    uint256 minAmountOut;
    address tokenIn;
    bytes extraData;
}

struct GetAmountOutParams {
    address router;
    address lpToken;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
}
