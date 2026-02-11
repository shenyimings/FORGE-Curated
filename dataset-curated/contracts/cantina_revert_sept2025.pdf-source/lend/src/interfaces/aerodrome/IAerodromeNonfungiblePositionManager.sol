// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

/// @title Aerodrome Slipstream Nonfungible Position Manager Interface
/// @notice Aerodrome's position manager is compatible with Uniswap V3
/// The main difference is that positions store tickSpacing instead of fee
/// However, since we can't override return types, we'll handle the conversion in our contracts
interface IAerodromeNonfungiblePositionManager is INonfungiblePositionManager {
    // Aerodrome uses the same interface as Uniswap V3
    // The positions() function returns fee (uint24) but it actually represents tickSpacing
    // We'll convert it using AerodromeHelper.tickSpacingToFee() when needed
}