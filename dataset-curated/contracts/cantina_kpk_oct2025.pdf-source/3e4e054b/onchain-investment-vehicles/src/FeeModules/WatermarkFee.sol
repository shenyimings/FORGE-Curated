// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPerfFeeModule} from "./IPerfFeeModule.sol";

/// @title WatermarkFee
/// @notice Calculates a performance fee based on the increase in price above a previous watermark.
/// The fee is only charged on profits above the last watermark.
contract WatermarkFee is IPerfFeeModule {
    /// @notice The current high watermark (highest share price seen)
    uint256 public highWatermark;

    /// @notice The total supply of shares when fees were last calculated
    uint256 public lastTotalSupply;

    /// @notice Events
    /// @param oldWatermark The previous watermark value
    /// @param newWatermark The new watermark value
    event WatermarkUpdated(uint256 oldWatermark, uint256 newWatermark);

    /// @notice Event emitted when performance fee is calculated
    /// @param fee The calculated performance fee amount
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals)
    /// @param timeElapsed The time elapsed since last calculation
    event PerformanceFeeCalculated(uint256 fee, uint256 sharesPrice, uint256 timeElapsed);

    /// @notice Calculates the performance fee for the IPerfFeeModule interface.
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    /// @param timeElapsed The time elapsed since last calculation
    /// @param feePct The performance fee percentage in basis points
    /// @param netSupply The net supply of shares (totalSupply - feeReceiverBalance), used as the base for fee calculations
    /// @return fee The performance fee amount in shares
    function calculatePerformanceFee(uint256 sharesPrice, uint256 timeElapsed, uint256 feePct, uint256 netSupply)
        external
        returns (uint256 fee)
    {
        // Store the previous watermark before potentially updating it
        uint256 previousWatermark = highWatermark;

        // Check if there's profit above the previous watermark
        if (sharesPrice <= previousWatermark) {
            return 0;
        } else {
            // Only update and emit if the watermark actually changes
            if (highWatermark != sharesPrice) {
                highWatermark = sharesPrice;
                emit WatermarkUpdated(previousWatermark, highWatermark);
            }
        }

        // Calculate profit above the previous watermark
        uint256 profitPerShare = highWatermark - previousWatermark;

        // Calculate total profit across net supply (excluding fee receiver balance)
        // This is consistent with how management fees are calculated
        uint256 totalProfit = (profitPerShare * netSupply) / highWatermark;

        // Calculate fee: totalProfit * feePct / 10000
        fee = (totalProfit * feePct) / 10_000;

        // Emit event with timeElapsed for transparency
        emit PerformanceFeeCalculated(fee, sharesPrice, timeElapsed);
    }
}
