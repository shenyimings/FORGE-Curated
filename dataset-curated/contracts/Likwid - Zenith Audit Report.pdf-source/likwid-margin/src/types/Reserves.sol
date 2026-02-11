// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "../libraries/Math.sol";
import {FixedPoint96} from "../libraries/FixedPoint96.sol";
import {BalanceDelta} from "./BalanceDelta.sol";

/// @dev Two `uint128` values packed into a single `uint256` where the upper 128 bits represent reserve0
/// and the lower 128 bits represent reserve1.
type Reserves is uint256;

using ReservesLibrary for Reserves global;

/// @notice Creates a Reserves object from two uint128 values.
/// @param _reserve0 The value for the upper 128 bits.
/// @param _reserve1 The value for the lower 128 bits.
/// @return A Reserves object.
function toReserves(uint128 _reserve0, uint128 _reserve1) pure returns (Reserves) {
    return Reserves.wrap((uint256(_reserve0) << 128) | _reserve1);
}

enum ReservesType {
    REAL,
    MIRROR,
    PAIR,
    LEND
}

/// @notice A library for handling the Reserves type, which packs two uint128 values into a single uint256.
library ReservesLibrary {
    struct UpdateParam {
        ReservesType _type;
        BalanceDelta delta;
    }

    error NotEnoughReserves();

    error InvalidReserves();

    /// @notice Retrieves the reserve0 value from a Reserves object.
    /// @param self The Reserves object.
    /// @return The reserve0 value (upper 128 bits).
    function reserve0(Reserves self) internal pure returns (uint128) {
        return uint128(Reserves.unwrap(self) >> 128);
    }

    /// @notice Retrieves the reserve1 value from a Reserves object.
    /// @param self The Reserves object.
    /// @return The reserve1 value (lower 128 bits).
    function reserve1(Reserves self) internal pure returns (uint128) {
        return uint128(Reserves.unwrap(self));
    }

    /// @notice Retrieves one of the reserves based on a boolean flag.
    /// @param self The Reserves object.
    /// @param forOne If true, returns reserve1; otherwise, returns reserve0.
    /// @return The selected reserve value.
    function reserve01(Reserves self, bool forOne) internal pure returns (uint128) {
        return forOne ? self.reserve1() : self.reserve0();
    }

    /// @notice Retrieves both reserve values from a Reserves object.
    /// @param self The Reserves object.
    /// @return _reserve0 The reserve0 value.
    /// @return _reserve1 The reserve1 value.
    function reserves(Reserves self) internal pure returns (uint128 _reserve0, uint128 _reserve1) {
        _reserve0 = self.reserve0();
        _reserve1 = self.reserve1();
    }

    /// @notice Updates the reserve0 value in a Reserves object.
    /// @param self The Reserves object to update.
    /// @param newReserve0 The new value for reserve0.
    /// @return The updated Reserves object.
    function updateReserve0(Reserves self, uint128 newReserve0) internal pure returns (Reserves) {
        return toReserves(newReserve0, self.reserve1());
    }

    /// @notice Updates the reserve1 value in a Reserves object.
    /// @param self The Reserves object to update.
    /// @param newReserve1 The new value for reserve1.
    /// @return The updated Reserves object.
    function updateReserve1(Reserves self, uint128 newReserve1) internal pure returns (Reserves) {
        return toReserves(self.reserve0(), newReserve1);
    }

    function applyDelta(Reserves self, BalanceDelta delta, bool enableOverflow) internal pure returns (Reserves) {
        (uint128 r0, uint128 r1) = self.reserves();
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        unchecked {
            if (d0 > 0) {
                uint128 amount0 = uint128(d0);
                if (r0 < amount0) {
                    if (enableOverflow) {
                        r0 = amount0;
                    } else {
                        revert NotEnoughReserves();
                    }
                }
                r0 -= amount0;
            } else if (d0 < 0) {
                r0 += uint128(-d0);
            }

            if (d1 > 0) {
                uint128 amount1 = uint128(d1);
                if (r1 < amount1) {
                    if (enableOverflow) {
                        r1 = amount1;
                    } else {
                        revert NotEnoughReserves();
                    }
                }
                r1 -= amount1;
            } else if (d1 < 0) {
                r1 += uint128(-d1);
            }
        }

        return toReserves(r0, r1);
    }

    /// @notice Applies a balance delta to the reserves.
    /// @param self The Reserves object.
    /// @param delta The balance delta to apply.
    /// @return The updated Reserves object.
    function applyDelta(Reserves self, BalanceDelta delta) internal pure returns (Reserves) {
        return applyDelta(self, delta, false);
    }

    /// @notice Calculates the price of token0 in terms of token1, scaled by Q96.
    /// @param self The Reserves object.
    /// @return The price of token0, scaled by Q96.
    function getPrice0X96(Reserves self) internal pure returns (uint256) {
        (uint128 r0, uint128 r1) = self.reserves();
        if (r0 == 0 || r1 == 0) revert InvalidReserves();
        return Math.mulDiv(r1, FixedPoint96.Q96, r0);
    }

    /// @notice Calculates the price of token1 in terms of token0, scaled by Q96.
    /// @param self The Reserves object.
    /// @return The price of token1, scaled by Q96.
    function getPrice1X96(Reserves self) internal pure returns (uint256) {
        (uint128 r0, uint128 r1) = self.reserves();
        if (r0 == 0 || r1 == 0) revert InvalidReserves();
        return Math.mulDiv(r0, FixedPoint96.Q96, r1);
    }

    /// @notice Checks if both reserves are positive.
    /// @param self The Reserves object.
    /// @return True if both reserves are positive, false otherwise.
    function bothPositive(Reserves self) internal pure returns (bool) {
        (uint128 r0, uint128 r1) = self.reserves();
        return r0 > 0 && r1 > 0;
    }
}
