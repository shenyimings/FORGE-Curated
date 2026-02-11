// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Router token swapping functionality
/// @notice Functions for swapping tokens via Pancake Stable Swap
interface IPancakeStableSwapRouter {
    /**
     * @param flag token amount in a stable swap pool. 2 for 2pool, 3 for 3pool
     */
    function exactInputStableSwap(
        address[] calldata path,
        uint256[] calldata flag,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external payable returns (uint256 amountOut);
}
