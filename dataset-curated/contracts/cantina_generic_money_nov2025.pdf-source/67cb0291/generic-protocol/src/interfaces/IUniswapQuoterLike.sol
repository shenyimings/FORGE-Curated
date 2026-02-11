// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IUniswapQuoterLike {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (uint256 amountOut);
}
