// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IUniswapRouter
 * @dev Interface for Uniswap V2/V3 style router
 * Simplified version with only the methods we need
 */
interface IUniswapRouter {
    /**
     * @dev Swaps an exact amount of input tokens for as many output tokens as possible
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens to receive
     * @param path An array of token addresses (path[0] = input token, path[path.length-1] = output token)
     * @param to Address to receive the output tokens
     * @param deadline Unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @dev Given an input amount of an asset and an array of token addresses, calculates all subsequent maximum output token amounts
     * @param amountIn The amount of input tokens
     * @param path An array of token addresses (path[0] = input token, path[path.length-1] = output token)
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts);
}
