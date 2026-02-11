// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "./lib/MathUtils.sol";
import {Ln} from "../../../lib/float128/src/Ln.sol";
import {Float128} from "../../../lib/float128/src/Float128.sol";
import {packedFloat} from "../../../lib/float128/src/Types.sol";

/**
 * @title Abstraction Layer between Equations and the underlying Math libraries
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 * @dev Wrapper functions to act as an abstraction layer between Equations and the Math library we're using.
 * @notice current implementation is using the float128 library for floating-point math operations.
 */
library MathLibs {
    using MathUtils for uint256;
    using Ln for packedFloat;
    using Float128 for packedFloat;
    using Float128 for int;

    uint256 constant WAD = 1e18;

    /**
     * @dev adds 2 signed floating point numbers
     * @param a the first addend
     * @param b the second addend
     * @return r the result of a + b
     * @notice this version of the function uses only the packedFloat type
     */
    function add(packedFloat a, packedFloat b) internal pure returns (packedFloat r) {
        r = a.add(b);
    }

    /**
     * @dev gets the difference between 2 signed floating point numbers
     * @param a the minuend
     * @param b the subtrahend
     * @return r the result of a - b
     * @notice this version of the function uses only the packedFloat type
     */
    function sub(packedFloat a, packedFloat b) internal pure returns (packedFloat r) {
        r = a.sub(b);
    }

    /**
     * @dev gets the multiplication of 2 signed floating point numbers
     * @param a the first factor
     * @param b the second factor
     * @return r the result of a * b
     * @notice this version of the function uses only the packedFloat type
     */
    function mul(packedFloat a, packedFloat b) internal pure returns (packedFloat r) {
        r = a.mul(b);
    }

    /**
     * @dev gets the division of 2 signed floating point numbers
     * @param a the numerator
     * @param b the denominator
     * @return r the result of a / b
     * @notice this version of the function uses only the packedFloat type
     */
    function div(packedFloat a, packedFloat b) internal pure returns (packedFloat r) {
        r = a.div(b);
    }

    function divL(packedFloat a, packedFloat b) internal pure returns (packedFloat r) {
        r = a.divL(b);
    }

    /**
     * @dev gets the square root of a signed floating point
     * @notice only positive numbers can get its square root calculated through this function
     * @param a the numerator to get the square root of
     * @return r the result of √a
     * @notice this version of the function uses only the packedFloat type
     */
    function sqrt(packedFloat a) internal pure returns (packedFloat r) {
        r = a.sqrt();
    }

    /**
     * @dev performs a greater than comparison
     * @param a the first term
     * @param b the second term
     * @return r retVal the result of a > b
     * @notice this version of the function uses only the packedFloat type
     */
    function gt(packedFloat a, packedFloat b) internal pure returns (bool r) {
        r = a.gt(b);
    }

    /**
     * @dev performs a less than comparison
     * @param a the first term
     * @param b the second term
     * @return r retVal the result of a < b
     * @notice this version of the function uses only the packedFloat type
     */
    function lt(packedFloat a, packedFloat b) internal pure returns (bool r) {
        r = a.lt(b);
    }

    /**
     * @dev performs a less or equal to comparison
     * @param a the first term
     * @param b the second term
     * @return r retVal the result of a < b
     * @notice this version of the function uses only the packedFloat type
     */
    function le(packedFloat a, packedFloat b) internal pure returns (bool r) {
        r = a.le(b);
    }

    /**
     * @dev performs an equality comparison
     * @param a the first term
     * @param b the second term
     * @return r true if a is equal to b
     * @notice this version of the function uses only the packedFloat type
     */
    function eq(packedFloat a, packedFloat b) internal pure returns (bool r) {
        r = a.eq(b);
    }

    /**
     * @dev encodes a pair of signed integer values describing a floating point number into a packedFloat
     * Examples: 1234.567 can be expressed as: 123456 x 10**(-3), or 1234560 x 10**(-4), or 12345600 x 10**(-5), etc.
     * @notice the mantissa can hold a maximum of 38 digits. Any number with more digits will lose precision.
     * @param mantissa the integer that holds the mantissa digits (38 digits max)
     * @param exponent the exponent of the floating point number (between -16384 and +16383)
     * @return float the encoded number. This value will ocupy a single 256-bit word and will hold the normalized
     * version of the floating-point number (shifts the exponent enough times to have exactly 38 significant digits)
     */
    function toPackedFloat(int mantissa, int exponent) internal pure returns (packedFloat float) {
        float = mantissa.toPackedFloat(exponent);
    }

    /**
     * @dev calculates the natural logarithm of a positive number
     * @param x the number to get the natural logarithm from
     * @return float the result of the natural logarithm of x as a float number
     */
    function ln(packedFloat x) internal pure returns (packedFloat float) {
        float = x.ln();
    }

    /**
     * @dev decodes a packedFloat into its mantissa and its exponent
     * @param float the floating-point number expressed as a packedFloat to decode
     * @return mantissa the 38 mantissa digits of the floating-point number
     * @return exponent the exponent of the floating-point number
     */
    function decode(packedFloat float) internal pure returns (int mantissa, int exponent) {
        (mantissa, exponent) = float.decode();
    }

    function convertpackedFloatToWAD(packedFloat value) internal pure returns (int256 result) {
        return convertpackedFloatToSpecificDecimals(value, 18);
    }

    /**
     * @dev converts a packedFloat to a specific number of decimals
     * @param value the packedFloat to convert
     * @param decimals the number of decimals to convert to
     * @return result the resulting number with the specified number of decimals
     */
    function convertpackedFloatToSpecificDecimals(packedFloat value, int decimals) internal pure returns (int256 result) {
        (int256 mantissa, int256 exponent) = value.decode();
        exponent *= -1;
        if (mantissa == 0) {
            result = 0;
        } else {
            if (exponent > decimals) {
                uint256 diff = uint(exponent - decimals);
                result = mantissa / int(10 ** diff);
            } else {
                uint256 diff = uint(decimals - exponent);
                result = mantissa * int(10 ** diff);
            }
        }
    }

    /**
     * @dev converts a packedFloat to a double WAD number
     * @param value the packedFloat to convert
     * @return result the resulting double WAD number
     */
    function convertpackedFloatToDoubleWAD(packedFloat value) internal pure returns (int256 result) {
        return convertpackedFloatToSpecificDecimals(value, 36);
    }
}
