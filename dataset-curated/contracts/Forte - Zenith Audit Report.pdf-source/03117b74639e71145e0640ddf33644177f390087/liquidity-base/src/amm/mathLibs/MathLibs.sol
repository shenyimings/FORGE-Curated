// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "solady/utils/FixedPointMathLib.sol";
import "./lib/MathUtils.sol";
import {LN} from "./lib/LN.sol";
import {Float128, Float, packedFloat} from "../../../lib/float128/src/Float128.sol";

/**
 * @title Abstraction Layer between Equations and the underlying Math libraries
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 * @dev Wrapper functions to act as an abstraction layer between Equations and the Math library we're using.
 * @notice current implementation is using the FixedPointMathLib library from Solady and the Solidity_Uint512 library
 */
library MathLibs {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;
    using MathUtils for uint256;
    using LN for uint256;
    using Float128 for int256;
    using Float128 for Float;
    using Float128 for packedFloat;

    uint256 constant WAD = FixedPointMathLib.WAD;

    /**
     * @dev Converts a WAD number to a raw number
     * @param value The number to be converted
     * @return result resulting raw number
     */
    function convertToRaw(uint256 value) internal pure returns (uint256 result) {
        result = value.convertToRaw();
    }

    /**
     * @param x the number to take the natural log of. Expressed as a WAD ** 2
     * @return result the ln of x multiplied by -1. Expressed as a WAD ** 2
     */
    function lnWAD2Negative(uint256 x) internal pure returns (uint256 result) {
        result = x.lnWAD2Negative();
    }

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
     * @dev adds 2 signed floating point numbers
     * @param a the first addend
     * @param b the second addend
     * @return r the result of a + b
     * @notice this version of the function uses only the Float type
     */
    function add(Float memory a, Float memory b) internal pure returns (Float memory r) {
        r = a.add(b);
    }

    /**
     * @dev gets the difference between 2 signed floating point numbers
     * @param a the minuend
     * @param b the subtrahend
     * @return r the result of a - b
     * @notice this version of the function uses only the Float type
     */
    function sub(Float memory a, Float memory b) internal pure returns (Float memory r) {
        r = a.sub(b);
    }

    /**
     * @dev gets the multiplication of 2 signed floating point numbers
     * @param a the first factor
     * @param b the second factor
     * @return r the result of a * b
     * @notice this version of the function uses only the Float type
     */
    function mul(Float memory a, Float memory b) internal pure returns (Float memory r) {
        r = a.mul(b);
    }

    /**
     * @dev gets the division of 2 signed floating point numbers
     * @param a the numerator
     * @param b the denominator
     * @return r the result of a / b
     * @notice this version of the function uses only the Float type
     */
    function div(Float memory a, Float memory b) internal pure returns (Float memory r) {
        r = a.div(b);
    }

    /**
     * @dev gets the square root of a signed floating point
     * @notice only positive numbers can get its square root calculated through this function
     * @param a the numerator to get the square root of
     * @return r the result of √a
     * @notice this version of the function uses only the Float type
     */
    function sqrt(Float memory a) internal pure returns (Float memory r) {
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
     * @dev decodes a packedFloat into its mantissa and its exponent
     * @param float the floating-point number expressed as a packedFloat to decode
     * @return mantissa the 38 mantissa digits of the floating-point number
     * @return exponent the exponent of the floating-point number
     */
    function decode(packedFloat float) internal pure returns (int mantissa, int exponent) {
        (mantissa, exponent) = float.decode();
    }

    /**
     * @dev shifts the exponent enough times to have a mantissa with exactly 38 digits
     * @notice this is a VITAL STEP to ensure the highest precision of the calculations
     * @param x the Float number to normalize
     * @return float the normalized version of x
     */
    function normalize(Float memory x) internal pure returns (Float memory float) {
        float = x.normalize();
    }

    /**
     * @dev packs a pair of signed integer values describing a floating-point number into a Float struct.
     * Examples: 1234.567 can be expressed as: 123456 x 10**(-3), or 1234560 x 10**(-4), or 12345600 x 10**(-5), etc.
     * @notice the mantissa can hold a maximum of 38 digits. Any number with more digits will lose precision.
     * @param _mantissa the integer that holds the mantissa digits (38 digits max)
     * @param _exponent the exponent of the floating point number (between -16384 and +16383)
     * @return float the normalized version of the floating-point number packed in a Float struct.
     */
    function toFloat(int _mantissa, int _exponent) internal pure returns (Float memory float) {
        float = _mantissa.toFloat(_exponent);
    }

    /**
     * @dev from Float to packedFloat
     * @param _float the Float number to encode into a packedFloat
     * @return float the packed version of Float
     */
    function convertToPackedFloat(Float memory _float) internal pure returns (packedFloat float) {
        float = _float.convertToPackedFloat();
    }

    /**
     * @dev from packedFloat to Float
     * @param _float the encoded floating-point number to unpack into a Float
     * @return float the unpacked version of packedFloat
     */
    function convertToUnpackedFloat(packedFloat _float) internal pure returns (Float memory float) {
        float = _float.convertToUnpackedFloat();
    }

    function convertpackedFloatToWAD(packedFloat value) internal pure returns (int256 result) {
        return convertpackedFloatToSpecificDecimals(value, 18);
    }

    function convertpackedFloatToSpecificDecimals(packedFloat value, int decimals) internal pure returns (int256 result) {
        (int256 mantissa, int256 exponent) = value.decode();
        exponent *= -1;
        if (mantissa == 0) {
            result = 0;
        } else {
            if (exponent > decimals) {
                uint256 diff = uint(exponent - decimals);
                result = int(uint(mantissa) / (10 ** diff));
            } else {
                uint256 diff = uint(decimals - exponent);
                result = int(uint(mantissa) * (10 ** diff));
            }
        }
    }

    function convertpackedFloatToDoubleWAD(packedFloat value) internal pure returns (int256 result) {
        return convertpackedFloatToSpecificDecimals(value, 36);
    }
}
