// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Library for bit operations.
library BitOps {
    // Calculates the number of leading zeros in binary representation.
    function clz(uint256 x) internal pure returns (uint256) {
        uint256 n = 256;
        uint256 y;

        y = x >> 128; if (y != 0) { n -= 128; x = y; }
        y = x >> 64;  if (y != 0) { n -= 64;  x = y; }
        y = x >> 32;  if (y != 0) { n -= 32;  x = y; }
        y = x >> 16;  if (y != 0) { n -= 16;  x = y; }
        y = x >> 8;   if (y != 0) { n -= 8;   x = y; }
        y = x >> 4;   if (y != 0) { n -= 4;   x = y; }
        y = x >> 2;   if (y != 0) { n -= 2;   x = y; }
        y = x >> 1;   if (y != 0) return n - 2;
        return n - x;
    }

    int256 constant MASK128 = 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    int256 constant MASK64 = 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF;
    int256 constant MASK32 = 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF;
    int256 constant MASK16 = 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF;
    int256 constant MASK8 = 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF;
    int256 constant MASK4 = 0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F;
    int256 constant MASK2 = 0x3333333333333333333333333333333333333333333333333333333333333333;
    int256 constant MASK1 = 0x5555555555555555555555555555555555555555555555555555555555555555;

    // Calculates the number of trailing zeros in binary representation. 
    function ctz(uint256 x) internal pure returns (uint256) {
        require(x <= uint256(type(int256).max), "Input exceeds maximum int256 value");
        uint256 c = 256; 

        int256 v = -int256(x);
        v = v & int256(x);
        if (v != 0) {
            c--;
        }
        if (v & MASK128 != 0) {
            c -= 128;
        }
        if (v & MASK64 != 0) {
            c -= 64;
        }
        if (v & MASK32 != 0) {
            c -= 32;
        }
        if (v & MASK16 != 0) {
            c -= 16;
        }
        if (v & MASK8 != 0) {
            c -= 8;
        }
        if (v & MASK4 != 0) {
            c -= 4;
        }
        if (v & MASK2 != 0) {
            c -= 2;
        }
        if (v & MASK1 != 0) {
            c -= 1;
        }

        return c;
    }
}