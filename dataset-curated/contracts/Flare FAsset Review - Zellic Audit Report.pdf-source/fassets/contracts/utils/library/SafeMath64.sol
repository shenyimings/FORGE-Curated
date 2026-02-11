// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;


library SafeMath64 {
    uint256 internal constant MAX_UINT64 = type(uint64).max;
    int256 internal constant MAX_INT64 = type(int64).max;

    error ConversionOverflow();
    error NegativeValue();

    // 64 bit signed/unsigned conversion

    function toUint64(int256 a) internal pure returns (uint64) {
        require(a >= 0, NegativeValue());
        require(a <= int256(MAX_UINT64), ConversionOverflow());
        return uint64(uint256(a));
    }

    function toInt64(uint256 a) internal pure returns (int64) {
        require(a <= uint256(MAX_INT64), ConversionOverflow());
        return int64(int256(a));
    }

    function max64(uint64 a, uint64 b) internal pure returns (uint64) {
        return a >= b ? a : b;
    }

    function min64(uint64 a, uint64 b) internal pure returns (uint64) {
        return a <= b ? a : b;
    }
}