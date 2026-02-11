// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library MathUtils {
    /**
     * Increases the value `x` to a whole multiple of `rounding`.
     */
    function roundUp(uint256 x, uint256 rounding) internal pure returns (uint256) {
        // division by 0 and overflow checks preformed by Solidity >= 0.8
        uint256 remainder = x % rounding;
        return remainder == 0 ? x : x - remainder + rounding;
    }

    /**
     * Return the positive part of `_a - _b`.
     */
    function subOrZero(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a > _b ? _a - _b : 0;
    }

    /**
     * Returns _x if it is positive, otherwise 0.
     */
    function positivePart(int256 _x) internal pure returns (uint256) {
        return _x >= 0 ? uint256(_x) : 0;
    }

    /**
     * Returns `_a <= _b`; works correctly when `_b` is any signed value.
     */
    function mixedLTE(uint256 _a, int256 _b) internal pure returns (bool) {
        return _b >= 0 && _a <= uint256(_b);
    }

    /**
     * Returns `_a <= _b`; works correctly when `_a` is any signed value.
     */
    function mixedLTE(int256 _a, uint256 _b) internal pure returns (bool) {
        return _a <= 0 || uint256(_a) <= _b;
    }
}
