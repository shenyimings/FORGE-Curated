 // SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @title LBRouter Interface
/// @notice Interface for the LBRouter contract
interface ILBRouter {
    /// @notice Represents the version of the LFJ Pair.
    enum Version {
        V1,
        V2,
        V2_1,
        V2_2
    }

    /// @notice Represents a path of tokens to swap through.
    /// @dev Contains an array of pairBinSteps, versions, and tokenPath.
    struct Path {
        uint256[] pairBinSteps;
        Version[] versions;
        IERC20[] tokenPath;
    }

    /// @notice Swaps an exact amount of tokens for another token, using the specified path.
    /// @param amountIn The amount of tokens to swap.
    /// @param amountOutMin The minimum amount of tokens to receive.
    /// @param path The path of tokens to swap through.
    /// @param to The address to send the swapped tokens to.
    /// @param deadline The deadline for the swap.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}