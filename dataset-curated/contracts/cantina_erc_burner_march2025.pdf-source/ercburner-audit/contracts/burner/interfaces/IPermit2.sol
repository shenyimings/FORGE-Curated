 // SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Permit2 Interface
/// @notice Interface for the Uniswap Permit2 contract
interface IPermit2 {
    /// @notice Approves a spender to spend a specific amount of tokens.
    /// @param token The address of the token to approve.
    /// @param spender The address of the spender.
    /// @param amount The amount of tokens to approve.
    /// @param expiration The expiration date of the approval.
    function approve(
        address token, 
        address spender, 
        uint160 amount, 
        uint48 expiration
    ) external;
}