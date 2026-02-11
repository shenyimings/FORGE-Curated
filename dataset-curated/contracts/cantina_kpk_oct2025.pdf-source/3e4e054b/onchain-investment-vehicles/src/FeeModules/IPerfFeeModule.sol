// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

/// @title IPerfFeeModule
/// @notice Interface for the performance fee module
/// @dev This interface is used to calculate the performance fee for a request
/// @dev The performance fee is calculated based on the shares price and the time elapsed
interface IPerfFeeModule {
    /// @notice Calculates the performance fee based on the provided parameters
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    /// @param timeElapsed The time elapsed since last calculation
    /// @param feePct The performance fee percentage in basis points
    /// @param netSupply The net supply of shares (totalSupply - feeReceiverBalance), used as the base for fee calculations
    /// @return The calculated performance fee amount
    function calculatePerformanceFee(uint256 sharesPrice, uint256 timeElapsed, uint256 feePct, uint256 netSupply)
        external
        returns (uint256);
}
