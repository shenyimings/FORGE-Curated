// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Math Library
 * @dev Library for handling decimal conversions and mathematical operations
 * @notice Provides safe arithmetic operations and decimal conversion utilities
 * @custom:precision Uses WAD (18 decimals) and RAY (27 decimals) precision
 */
library Math {
    /// @dev WAD precision constant (18 decimals)
    uint256 private constant WAD = 10 ** 18;

    /// @dev RAY precision constant (27 decimals)
    uint256 private constant RAY = 10 ** 27;

    /// @dev Half WAD for rounding in WAD operations
    uint256 private constant HALF_WAD = WAD / 2;

    /// @dev Half RAY for rounding in RAY operations
    uint256 private constant HALF_RAY = RAY / 2;

    /**
     * @dev Converts amount from any decimal precision to 18 decimals
     * @param amt Amount to convert
     * @param decimals Current decimal precision of the amount
     * @return Converted amount with 18 decimal precision
     * @notice Handles scaling up or down based on input decimals
     */
    function convertTo18(uint256 amt, uint256 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amt;
        if (decimals > 18) return amt / (10 ** (decimals - 18));
        return amt * (10 ** (18 - decimals));
    }

    /**
     * @dev Converts amount from 18 decimals to specified decimal precision
     * @param amt Amount with 18 decimal precision
     * @param decimals Target decimal precision
     * @return Converted amount with target decimal precision
     * @notice Handles scaling up or down to target decimals
     */
    function convert18ToDec(uint256 amt, uint256 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amt;
        if (decimals > 18) return amt * (10 ** (decimals - 18));
        return amt / (10 ** (18 - decimals));
    }

    /**
     * @dev Safe addition with overflow protection
     * @param x First operand
     * @param y Second operand
     * @return z Result of x + y
     * @custom:security Prevents arithmetic overflow
     */
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "Math: addition overflow detected");
    }

    /**
     * @dev Safe subtraction with underflow protection
     * @param x Minuend
     * @param y Subtrahend
     * @return z Result of x - y
     * @custom:security Prevents arithmetic underflow
     */
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Math: subtraction underflow detected");
    }

    /**
     * @dev Safe multiplication with overflow protection
     * @param x First operand
     * @param y Second operand
     * @return z Result of x * y
     * @custom:security Prevents arithmetic overflow
     */
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "Math: multiplication overflow detected");
    }

    /**
     * @dev Safe division with zero division protection
     * @param x Dividend
     * @param y Divisor
     * @return z Result of x / y
     * @custom:security Prevents division by zero
     */
    function div(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "Math: cannot divide by zero");
        z = x / y;
    }

    /**
     * @dev WAD precision multiplication with rounding
     * @param x First operand in WAD precision
     * @param y Second operand in WAD precision
     * @return z Result in WAD precision with proper rounding
     * @notice Multiplies two WAD values and maintains precision
     */
    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), HALF_WAD) / WAD;
    }

    /**
     * @dev WAD precision division with rounding
     * @param x Dividend in WAD precision
     * @param y Divisor (not necessarily in WAD precision)
     * @return z Result in WAD precision with proper rounding
     * @notice Divides WAD value by another value maintaining WAD precision
     */
    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, WAD), HALF_WAD) / y;
    }

    /**
     * @dev RAY precision multiplication with rounding
     * @param x First operand in RAY precision
     * @param y Second operand in RAY precision
     * @return z Result in RAY precision with proper rounding
     * @notice Multiplies two RAY values and maintains precision
     */
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), HALF_RAY) / RAY;
    }

    /**
     * @dev RAY precision division with rounding
     * @param x Dividend in RAY precision
     * @param y Divisor (not necessarily in RAY precision)
     * @return z Result in RAY precision with proper rounding
     * @notice Divides RAY value by another value maintaining RAY precision
     */
    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, RAY), HALF_RAY) / y;
    }

    /**
     * @dev Converts WAD precision to RAY precision
     * @param wad Value in WAD precision (18 decimals)
     * @return rad Value converted to RAY precision (27 decimals)
     * @notice Scales up from 18 to 27 decimal precision
     */
    function toRad(uint256 wad) internal pure returns (uint256 rad) {
        rad = mul(wad, 10 ** 27);
    }

    /**
     * @dev Safely converts uint256 to int256
     * @param x Unsigned integer to convert
     * @return y Signed integer result
     * @custom:security Prevents overflow when converting to signed integer
     */
    function toInt(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        require(y >= 0, "Math: integer conversion overflow detected");
    }
}
