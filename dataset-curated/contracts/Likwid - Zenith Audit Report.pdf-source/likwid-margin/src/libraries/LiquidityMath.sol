// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Math library for liquidity
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        assembly ("memory-safe") {
            z := add(and(x, 0xffffffffffffffffffffffffffffffff), signextend(15, y))
            if shr(128, z) {
                // revert SafeCastOverflow()
                mstore(0, 0x93dafdf1)
                revert(0, 4)
            }
        }
    }

    function addInvestment(uint256 prev, int128 amount0, int128 amount1) internal pure returns (uint256 current) {
        assembly ("memory-safe") {
            // Unpack prev into two 128-bit values
            let prevAmount0 := shr(128, prev)
            let prevAmount1 := and(prev, 0xffffffffffffffffffffffffffffffff)

            // Add deltas, checking for int128 overflow
            let currentAmount0 := add(signextend(15, prevAmount0), signextend(15, amount0))
            if iszero(eq(signextend(15, currentAmount0), currentAmount0)) {
                // revert SafeCastOverflow()
                mstore(0, 0x93dafdf1)
                revert(0, 4)
            }

            let currentAmount1 := add(signextend(15, prevAmount1), signextend(15, amount1))
            if iszero(eq(signextend(15, currentAmount1), currentAmount1)) {
                // revert SafeCastOverflow()
                mstore(0, 0x93dafdf1)
                revert(0, 4)
            }

            // Pack the results back into a uint256
            current := or(
                shl(128, and(currentAmount0, 0xffffffffffffffffffffffffffffffff)),
                and(currentAmount1, 0xffffffffffffffffffffffffffffffff)
            )
        }
    }
}