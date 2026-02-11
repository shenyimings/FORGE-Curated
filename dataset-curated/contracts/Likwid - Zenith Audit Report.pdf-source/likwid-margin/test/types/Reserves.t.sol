// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Reserves, ReservesLibrary, toReserves} from "../../src/types/Reserves.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {FixedPoint96} from "../../src/libraries/FixedPoint96.sol";

contract ReservesWrapper {
    function applyDelta(Reserves r, BalanceDelta delta) public pure returns (Reserves) {
        return r.applyDelta(delta);
    }

    function getPrice0X96(Reserves r) public pure returns (uint256) {
        return r.getPrice0X96();
    }
}

contract ReservesTest is Test {
    ReservesWrapper wrapper;

    function setUp() public {
        wrapper = new ReservesWrapper();
    }

    function testToReserves() public pure {
        Reserves r = toReserves(100, 200);
        (uint128 r0, uint128 r1) = r.reserves();
        assertEq(r0, 100);
        assertEq(r1, 200);
    }

    function testReserve0() public pure {
        Reserves r = toReserves(100, 200);
        assertEq(r.reserve0(), 100);
    }

    function testReserve1() public pure {
        Reserves r = toReserves(100, 200);
        assertEq(r.reserve1(), 200);
    }

    function testReserve01() public pure {
        Reserves r = toReserves(100, 200);
        assertEq(r.reserve01(false), 100);
        assertEq(r.reserve01(true), 200);
    }

    function testReserves() public pure {
        Reserves r = toReserves(100, 200);
        (uint128 r0, uint128 r1) = r.reserves();
        assertEq(r0, 100);
        assertEq(r1, 200);
    }

    function testUpdateReserve0() public pure {
        Reserves r = toReserves(100, 200);
        r = r.updateReserve0(150);
        (uint128 r0, uint128 r1) = r.reserves();
        assertEq(r0, 150);
        assertEq(r1, 200);
    }

    function testUpdateReserve1() public pure {
        Reserves r = toReserves(100, 200);
        r = r.updateReserve1(250);
        (uint128 r0, uint128 r1) = r.reserves();
        assertEq(r0, 100);
        assertEq(r1, 250);
    }

    function testApplyDeltaAdd() public pure {
        Reserves r = toReserves(100, 200);
        BalanceDelta delta = toBalanceDelta(-50, -50);
        r = r.applyDelta(delta);
        (uint128 r0, uint128 r1) = r.reserves();
        assertEq(r0, 150);
        assertEq(r1, 250);
    }

    function testApplyDeltaSubtract() public pure {
        Reserves r = toReserves(100, 200);
        BalanceDelta delta = toBalanceDelta(50, 50);
        r = r.applyDelta(delta);
        (uint128 r0, uint128 r1) = r.reserves();
        assertEq(r0, 50);
        assertEq(r1, 150);
    }

    function testApplyDeltaRevert() public {
        Reserves r = toReserves(100, 200);
        BalanceDelta delta = toBalanceDelta(150, 50);
        vm.expectRevert(ReservesLibrary.NotEnoughReserves.selector);
        wrapper.applyDelta(r, delta);
    }

    function testGetPrice0X96() public pure {
        Reserves r = toReserves(100, 200);
        uint256 price = r.getPrice0X96();
        assertEq(price, (uint256(200) * FixedPoint96.Q96) / 100);
    }

    function testGetPrice1X96() public pure {
        Reserves r = toReserves(100, 200);
        uint256 price = r.getPrice1X96();
        assertEq(price, (uint256(100) * FixedPoint96.Q96) / 200);
    }

    function testGetPriceRevert() public {
        Reserves r = toReserves(0, 200);
        vm.expectRevert(ReservesLibrary.InvalidReserves.selector);
        wrapper.getPrice0X96(r);
    }

    function testBothPositive() public pure {
        Reserves r1 = toReserves(100, 200);
        assertTrue(r1.bothPositive());

        Reserves r2 = toReserves(0, 200);
        assertFalse(r2.bothPositive());

        Reserves r3 = toReserves(100, 0);
        assertFalse(r3.bothPositive());

        Reserves r4 = toReserves(0, 0);
        assertFalse(r4.bothPositive());
    }
}