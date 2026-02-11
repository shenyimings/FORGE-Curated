// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @title Helper functions for Aerodrome integration
/// @notice Aerodrome Slipstream pools use tick spacing directly instead of fee tiers
/// @dev Unlike Uniswap V3 which has fixed fee tiers mapped to tick spacings,
///      Aerodrome allows arbitrary fees for any tick spacing. The tick spacing
///      is immutable once a pool is created, but fees can be dynamic.
library AerodromeHelper {
    // No conversion functions needed - Aerodrome stores tickSpacing directly
    // in the position data where Uniswap V3 would store the fee tier.
    // The tickSpacing is immutable for a pool and is used to identify the pool
    // along with the token pair.
}