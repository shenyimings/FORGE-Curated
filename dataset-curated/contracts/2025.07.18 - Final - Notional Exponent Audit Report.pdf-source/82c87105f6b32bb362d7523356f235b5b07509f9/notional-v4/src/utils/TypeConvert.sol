// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

library TypeConvert {

    function toUint(int256 x) internal pure returns (uint256) {
        require(x >= 0);
        return uint256(x);
    }

    function toInt(uint256 x) internal pure returns (int256) {
        require (x <= uint256(type(int256).max)); // dev: toInt overflow
        return int256(x);
    }

    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= uint128(type(uint128).max)); // dev: toUint128 overflow
        return uint128(x);
    }

    function toUint120(uint256 x) internal pure returns (uint120) {
        require(x <= uint120(type(uint120).max)); // dev: toUint120 overflow
        return uint120(x);
    }

}
