// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.26;

library StageMath {
    function add(uint256 stage, uint128 amount) internal pure returns (uint256) {
        (uint128 _total, uint128 _liquidity) = decode(stage);
        _total += amount;
        _liquidity += amount;
        return (uint256(_total) << 128) | uint256(_liquidity & ((1 << 128) - 1));
    }

    function sub(uint256 stage, uint128 amount) internal pure returns (uint256) {
        (uint128 _total, uint128 _liquidity) = decode(stage);
        _liquidity -= amount;
        return (uint256(_total) << 128) | uint256(_liquidity & ((1 << 128) - 1));
    }

    function subTotal(uint256 stage, uint128 amount) internal pure returns (uint256) {
        (uint128 _total, uint128 _liquidity) = decode(stage);
        _total -= amount;
        _liquidity -= amount;
        return (uint256(_total) << 128) | uint256(_liquidity & ((1 << 128) - 1));
    }

    function isFree(uint256 stage, uint32 leavePart) internal pure returns (bool) {
        (uint128 total, uint128 liquidity) = decode(stage);
        if (leavePart == 0) {
            leavePart = 2;
        }
        return total / leavePart >= liquidity;
    }

    function decode(uint256 stage) internal pure returns (uint128 total, uint128 liquidity) {
        if (stage == 0) {
            return (0, 0);
        }
        total = uint128(stage >> 128);
        liquidity = uint128(stage & ((1 << 128) - 1));
    }
}
