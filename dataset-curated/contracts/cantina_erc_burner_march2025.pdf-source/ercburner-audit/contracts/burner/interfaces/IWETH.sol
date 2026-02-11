 // SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title WETH Interface
/// @notice Interface for the Wrapped ETH contract
interface IWETH {
    /// @notice Withdraws a specific amount of ETH from the contract.
    /// @param amount The amount of ETH to withdraw.
    function withdraw(uint256 amount) external;
}