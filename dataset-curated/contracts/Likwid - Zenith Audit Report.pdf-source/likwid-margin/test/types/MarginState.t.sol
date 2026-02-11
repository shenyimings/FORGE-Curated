// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge
import {Test} from "forge-std/Test.sol";
// Likwid Contracts
import {MarginState} from "../../src/types/MarginState.sol";

contract MarginStateTest is Test {
    MarginState private marginState;

    function setUp() public {
        marginState = MarginState.wrap(0);
    }

    function testSetAndGetRateBase() public {
        uint24 rateBase = 1000;
        marginState = marginState.setRateBase(rateBase);
        assertEq(marginState.rateBase(), rateBase);
    }

    function testSetAndGetUseMiddleLevel() public {
        uint24 useMiddleLevel = 2000;
        marginState = marginState.setUseMiddleLevel(useMiddleLevel);
        assertEq(marginState.useMiddleLevel(), useMiddleLevel);
    }

    function testSetAndGetUseHighLevel() public {
        uint24 useHighLevel = 3000;
        marginState = marginState.setUseHighLevel(useHighLevel);
        assertEq(marginState.useHighLevel(), useHighLevel);
    }

    function testSetAndGetMLow() public {
        uint24 mLow = 4000;
        marginState = marginState.setMLow(mLow);
        assertEq(marginState.mLow(), mLow);
    }

    function testSetAndGetMMiddle() public {
        uint24 mMiddle = 5000;
        marginState = marginState.setMMiddle(mMiddle);
        assertEq(marginState.mMiddle(), mMiddle);
    }

    function testSetAndGetMHigh() public {
        uint24 mHigh = 6000;
        marginState = marginState.setMHigh(mHigh);
        assertEq(marginState.mHigh(), mHigh);
    }

    function testMultipleSetAndGet() public {
        uint24 rateBase = 1000;
        uint24 useMiddleLevel = 2000;
        uint24 useHighLevel = 3000;
        uint24 mLow = 4000;
        uint24 mMiddle = 5000;
        uint24 mHigh = 6000;

        marginState = marginState.setRateBase(rateBase);
        marginState = marginState.setUseMiddleLevel(useMiddleLevel);
        marginState = marginState.setUseHighLevel(useHighLevel);
        marginState = marginState.setMLow(mLow);
        marginState = marginState.setMMiddle(mMiddle);
        marginState = marginState.setMHigh(mHigh);

        assertEq(marginState.rateBase(), rateBase);
        assertEq(marginState.useMiddleLevel(), useMiddleLevel);
        assertEq(marginState.useHighLevel(), useHighLevel);
        assertEq(marginState.mLow(), mLow);
        assertEq(marginState.mMiddle(), mMiddle);
        assertEq(marginState.mHigh(), mHigh);
    }
}
