// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

uint256 constant WAD = 1e18;

/// @title MathsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.org
/// @notice Library to manage fixed-point arithmetic.
library MathsLib {
    /// @dev Returns (`x` * `y`) / `WAD` rounded down.
    function wadMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    /// @dev Returns (`x` * `y`) / `WAD` rounded up.
    function wadMulUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD);
    }

    /// @dev Returns (`x` * `WAD`) / `y` rounded down.
    function wadDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    /// @dev Returns (`x` * `WAD`) / `y` rounded up.
    function wadDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    /// @dev Returns (`x` * `y`) / `d` rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (`x` * `y`) / `d` rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev Returns the absolute value of `x`.
    function abs(int256 x) internal pure returns (uint256 y) {
        assembly ("memory-safe") {
            y := xor(sar(255, x), add(sar(255, x), x))
        }
    }

    /// @dev Returns the negative value of `x`.
    function neg(uint256 x) internal pure returns (int256 y) {
        assembly ("memory-safe") {
            y := sub(0, x)
        }
    }
}
