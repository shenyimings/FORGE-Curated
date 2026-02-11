// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Constants
/// @notice Presents common constants.
library Constants {
    /// @notice The maximum Stability Pools configured.
    uint256 internal constant MAX_SP = 3;
    /// @notice The maximum value in BPS.
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    /// @notice The fee in BPS.
    uint256 internal constant BPS_MAX_FEE = 500;
    /// @notice The minimum reward in BPS.
    uint256 internal constant BPS_MIN_REWARD = 50;
    /// @notice The minimum reward in BPS.
    uint256 internal constant BPS_MAX_REWARD = 1_000;
    /// @notice The upper boundary for maximum slippage tolerance in BPS.
    uint256 internal constant BPS_MAX_SLIPPAGE = 1_000;
    /// @notice The upper boundary for maximum collateral denominated in $BOLD.
    uint256 internal constant MAX_COLL_IN_BOLD_UPPER_BOUND = 7_500e18;
    /// @notice The price precision returned from oracle.
    uint256 internal constant ORACLE_PRICE_PRECISION = 18;
}
