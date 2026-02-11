// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Get the expected return amount for swapping tokens via Pancake Stable Swap
/// @notice Functions for getting the expected return amount for swapping tokens via Pancake Stable Swap
interface IPancakeStableSwapPool {
    function balances(uint256) external view returns (uint256);

    function get_dy(
        uint256 token0,
        uint256 token1,
        uint256 inputAmount
    ) external view returns (uint256 outputAmount);
}
