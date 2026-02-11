// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Interface for the Uniswap V2 Router
/// @dev https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Router02.sol
interface IUniswapV2Router02 {
    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param amountIn The amount of token to swap
    /// @param amountOutMin The minimum amount of output that must be received
    /// @param path The ordered list of tokens to swap through
    /// @param to The recipient address
    /// @return amounts The amounts of the swapped tokens
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// that may remain in the router after the swap.
    /// @param amountOut The amount of token to receive
    /// @param amountInMax The maximum amount of token to swap
    /// @param path The ordered list of tokens to swap through
    /// @param to The recipient address
    /// @return amounts The amounts of the swapped tokens
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
