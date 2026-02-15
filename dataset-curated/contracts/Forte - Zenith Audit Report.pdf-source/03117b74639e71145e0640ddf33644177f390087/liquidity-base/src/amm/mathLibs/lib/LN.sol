// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "solady/utils/FixedPointMathLib.sol";

library LN {
    using FixedPointMathLib for uint256;
    uint constant M = 36; // the number of precision decimals (WAD ** 2)
    uint constant one = 10 ** M;
    uint constant ln2WAD2 = 693147180559945309417232121458176568;
    uint constant ln1point1WAD2 = 95310179804324860043952123280765092;

    /**
     * @dev Computes the  the number of bits needed to shift x to the left to get a value between 0.5 and 1 (WAD**2)
     * @param x the number to compute the number of bits needed to shift to the left to get between 0.5 and 1 (WAD**2)
     * @return k the number of bits needed to shift to the left to get x between 0.5 and 1 (WAD**2)
     */
    function _compute_sutable_k(uint x) private pure returns (uint) {
        // first approximation
        /// log2(x/(10**M))  = - (log2(10**M) - log2(x)) where log2(10**M) = 119
        uint initial_k = 119 - x.log2(); // the number of bits I need to shift to the left to get x between 0.5 and 1 (WAD**2)
        // we find the exact k
        uint start = initial_k <= 1 ? 0 : initial_k - 1;
        uint a = (2 ** start) * x;
        for (uint k = start; k <= initial_k + 1; k++) {
            a = a << 1;
            if (a > one) return k;
        }
        revert("k not found");
    }

    /**
     * @dev Computes the  the number of times that (2 ** k) * x needs to be multiplied by 1.1 to be as close as possibe to 1 (WAD**2)
     * @param new_x defined as (2 ** k) * x
     * @return q the number of times that new_x needs to be multiplied by 1.1 to be as close as possibe to 1 (WAD**2)
     */
    function _compute_suitable_q(uint new_x) private pure returns (uint) {
        if (new_x <= one >> 1 || new_x > one) revert("x not in range");
        uint a = new_x;
        for (uint q = 0; q <= 7; q++) {
            a = (11 * a) / 10;
            if (a > one) return q;
        }
        revert("q not found");
    }

    /**
     * @dev Computes the absolute value of the natural log of x where x is a positive number
     * less than 1 and is expressed as a WAD ** 2 (36 decimal places)
     * @param x the number to take the natural log of. Expected to be expressed as a WAD ** 2
     * @return result the ln of x multiplied by -1. Expressed as a WAD ** 2
     * @notice to properly use the result of this function, multiply by -1, or use as -result
     */
    function lnWAD2Negative(uint256 x) internal pure returns (uint256 result) {
        if (x > one) revert("function lnWAD2Negative only accepts values less than or equal to 1");
        if (x == 0) revert("natural logarithm of 0 is negative infinity");
        uint k = _compute_sutable_k(x);
        uint q = _compute_suitable_q(2 ** k * x);
        uint z = one - ((2 ** k) * x * (11 ** q)) / (10 ** q);
        // slither-disable-start divide-before-multiply
        // 25 represents the Taylor terms in a Taylor series
        result = one / 25;
        for (uint i = 0; i < 25; i++) {
            uint l = 25 - i - 1;
            if (l > 0) result = ((result * z) / one) + one / l;
            else result = (result * z) / one;
        }
        // slither-disable-end divide-before-multiply
        result = result + k * ln2WAD2 + q * ln1point1WAD2;
    }
}
