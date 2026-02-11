// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MarginLevels, MarginLevelsLibrary} from "../../src/types/MarginLevels.sol";

contract MarginLevelsTest is Test {
    using MarginLevelsLibrary for MarginLevels;

    MarginLevels private marginLevels;

    function setUp() public {
        marginLevels = marginLevels.setMinMarginLevel(1170000);
        marginLevels = marginLevels.setMinBorrowLevel(1400000);
        marginLevels = marginLevels.setLiquidateLevel(1100000);
        marginLevels = marginLevels.setLiquidationRatio(950000);
        marginLevels = marginLevels.setCallerProfit(10000);
        marginLevels = marginLevels.setProtocolProfit(5000);
    }

    function test_Getters() public {
        assertEq(marginLevels.minMarginLevel(), 1170000);
        assertEq(marginLevels.minBorrowLevel(), 1400000);
        assertEq(marginLevels.liquidateLevel(), 1100000);
        assertEq(marginLevels.liquidationRatio(), 950000);
        assertEq(marginLevels.callerProfit(), 10000);
        assertEq(marginLevels.protocolProfit(), 5000);
    }

    function test_SetMinMarginLevel() public {
        uint24 newLevel = 1200000;
        marginLevels = marginLevels.setMinMarginLevel(newLevel);
        assertEq(marginLevels.minMarginLevel(), newLevel);
        // check other values are unchanged
        assertEq(marginLevels.minBorrowLevel(), 1400000);
    }

    function test_SetMinBorrowLevel() public {
        uint24 newLevel = 1500000;
        marginLevels = marginLevels.setMinBorrowLevel(newLevel);
        assertEq(marginLevels.minBorrowLevel(), newLevel);
        // check other values are unchanged
        assertEq(marginLevels.minMarginLevel(), 1170000);
    }

    function test_SetLiquidateLevel() public {
        uint24 newLevel = 1050000;
        marginLevels = marginLevels.setLiquidateLevel(newLevel);
        assertEq(marginLevels.liquidateLevel(), newLevel);
        // check other values are unchanged
        assertEq(marginLevels.minMarginLevel(), 1170000);
    }

    function test_SetLiquidationRatio() public {
        uint24 newRatio = 900000;
        marginLevels = marginLevels.setLiquidationRatio(newRatio);
        assertEq(marginLevels.liquidationRatio(), newRatio);
        // check other values are unchanged
        assertEq(marginLevels.minMarginLevel(), 1170000);
    }

    function test_SetCallerProfit() public {
        uint24 newProfit = 20000;
        marginLevels = marginLevels.setCallerProfit(newProfit);
        assertEq(marginLevels.callerProfit(), newProfit);
        // check other values are unchanged
        assertEq(marginLevels.minMarginLevel(), 1170000);
    }

    function test_SetProtocolProfit() public {
        uint24 newProfit = 7500;
        marginLevels = marginLevels.setProtocolProfit(newProfit);
        assertEq(marginLevels.protocolProfit(), newProfit);
        // check other values are unchanged
        assertEq(marginLevels.minMarginLevel(), 1170000);
    }
}