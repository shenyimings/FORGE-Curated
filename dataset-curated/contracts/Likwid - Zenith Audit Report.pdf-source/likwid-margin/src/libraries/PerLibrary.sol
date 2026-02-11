// SPDX-License-Identifier: MIT
// Likwid Contracts
pragma solidity ^0.8.0;

import {Math} from "./Math.sol";

library PerLibrary {
    error InvalidMillionth();

    uint256 public constant ONE_MILLION = 10 ** 6;
    uint256 public constant ONE_TRILLION = 10 ** 12;
    uint256 public constant YEAR_TRILLION_SECONDS = ONE_TRILLION * 365 * 24 * 3600;

    function mulMillion(uint256 x) internal pure returns (uint256 y) {
        y = x * ONE_MILLION;
    }

    function divMillion(uint256 x) internal pure returns (uint256 y) {
        y = x / ONE_MILLION;
    }

    function mulMillionDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = Math.mulDiv(x, ONE_MILLION, y);
    }

    function mulDivMillion(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = Math.mulDiv(x, y, ONE_MILLION);
    }

    function upperMillion(uint256 x, uint256 per) internal pure returns (uint256 z) {
        z = Math.mulDiv(x, ONE_MILLION + per, ONE_MILLION);
    }

    function lowerMillion(uint256 x, uint256 per) internal pure returns (uint256 z) {
        if (per >= ONE_MILLION) {
            return z;
        }
        z = Math.mulDiv(x, ONE_MILLION - per, ONE_MILLION);
    }

    function isWithinTolerance(uint256 a, uint256 b, uint256 t) internal pure returns (bool) {
        return a >= b ? (a - b) <= t : (b - a) <= t;
    }
}
