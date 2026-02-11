// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ExternalTrade } from "src/types/Trades.sol";

/// @title TokenSwapAdapter
/// @notice Abstract contract for token swap adapters
abstract contract TokenSwapAdapter {
    /// @notice Executes series of token swaps and returns the hashes of the orders submitted/executed
    /// @param externalTrades The external trades to execute
    function executeTokenSwap(ExternalTrade[] calldata externalTrades, bytes calldata data) external payable virtual;

    /// @notice Completes the token swaps by confirming each order settlement and claiming the resulting tokens (if
    /// necessary).
    /// @dev This function must return the exact amounts of sell tokens and buy tokens claimed per trade.
    /// If the adapter operates asynchronously (e.g., CoWSwap), this function should handle the following:
    /// - Cancel any unsettled trades to prevent further execution.
    /// - Claim the remaining tokens from the unsettled trades.
    ///
    /// @param externalTrades The external trades that were executed and need to be settled.
    /// @return claimedAmounts A 2D array where each element contains the claimed amounts of sell tokens and buy tokens
    /// for each corresponding trade in `externalTrades`. The first element of each sub-array is the claimed sell
    /// amount, and the second element is the claimed buy amount.
    function completeTokenSwap(ExternalTrade[] calldata externalTrades)
        external
        payable
        virtual
        returns (uint256[2][] memory claimedAmounts);
}
