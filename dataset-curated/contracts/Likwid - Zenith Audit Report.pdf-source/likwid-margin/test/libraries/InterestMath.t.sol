// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {InterestMath} from "../../src/libraries/InterestMath.sol";
import {MarginState, MarginStateLibrary} from "../../src/types/MarginState.sol";
import {Reserves, toReserves} from "../../src/types/Reserves.sol";


contract InterestMathTest is Test {
    using MarginStateLibrary for MarginState;

    MarginState internal marginState;

    function setUp() public {
        marginState = marginState
            .setRateBase(20000)
            .setUseMiddleLevel(700000)
            .setUseHighLevel(900000)
            .setMLow(500)
            .setMMiddle(5000)
            .setMHigh(50000);
    }

    function test_getBorrowRateByReserves() public view {
        uint256 borrowReserve = 1000e18;
        uint256 mirrorReserve = 100e18;
        uint256 rate = InterestMath.getBorrowRateByReserves(marginState, borrowReserve, mirrorReserve);
        console.log("rate", rate);
        assertTrue(rate > marginState.rateBase());
    }

    function test_getBorrowRateCumulativeLast() public view {
        uint256 timeElapsed = 3600;
        uint256 rate0CumulativeBefore = 1e18;
        uint256 rate1CumulativeBefore = 1e18;
        Reserves realReserves = toReserves(uint128(1000e18), uint128(1000e18));
        Reserves mirrorReserve = toReserves(uint128(100e18), uint128(200e18));

        (uint256 rate0CumulativeLast, uint256 rate1CumulativeLast) = InterestMath.getBorrowRateCumulativeLast(
            timeElapsed,
            rate0CumulativeBefore,
            rate1CumulativeBefore,
            marginState,
            realReserves,
            mirrorReserve
        );

        assertTrue(rate0CumulativeLast > rate0CumulativeBefore);
        assertTrue(rate1CumulativeLast > rate1CumulativeBefore);
    }

    function test_updateInterestForOne() public pure {
        InterestMath.InterestUpdateParams memory params = InterestMath.InterestUpdateParams({
            mirrorReserve: 100e18,
            borrowCumulativeLast: 1.1e18,
            borrowCumulativeBefore: 1e18,
            interestReserve: 0,
            pairReserve: 500e18,
            lendReserve: 500e18,
            depositCumulativeLast: 1e18,
            protocolFee: 0
        });

        InterestMath.InterestUpdateResult memory result = InterestMath.updateInterestForOne(params);

        assertTrue(result.changed);
        assertTrue(result.newMirrorReserve > params.mirrorReserve);
        assertTrue(result.newPairReserve > params.pairReserve);
        assertTrue(result.newLendReserve > params.lendReserve);
        assertTrue(result.newDepositCumulativeLast > params.depositCumulativeLast);
        assertEq(result.newInterestReserve, 0);
    }
}