// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SwapMath} from "../../src/libraries/SwapMath.sol";
import {Reserves, toReserves} from "../../src/types/Reserves.sol";
import {FeeLibrary} from "../../src/libraries/FeeLibrary.sol";

contract SwapMathTest is Test {
    using FeeLibrary for uint24;

    Reserves testReserves;
    Reserves testTruncatedReserves;

    function setUp() public {
        testReserves = toReserves(1000e18, 1000e18);
        testTruncatedReserves = toReserves(1000e18, 1000e18);
    }

    // =========================================
    // differencePrice Tests
    // =========================================

    function testDifferencePrice_Positive() public pure {
        assertEq(SwapMath.differencePrice(110, 100), 10, "Test 1");
        assertEq(SwapMath.differencePrice(100, 110), 10, "Test 2");
    }

    function testDifferencePrice_Zero() public pure {
        assertEq(SwapMath.differencePrice(100, 100), 0, "Test 3");
    }

    // =========================================
    // dynamicFee Tests
    // =========================================

    function testDynamicFee_NoChange() public pure {
        uint24 baseFee = 3000;
        uint256 degree = 100000; // 10%
        uint24 dynamic = SwapMath.dynamicFee(baseFee, degree);
        assertEq(dynamic, baseFee, "Fee should not change for low degree");
    }

    function testDynamicFee_Increases() public pure {
        uint24 baseFee = 3000;
        uint256 degree = 200000; // 20%
        uint24 dynamic = SwapMath.dynamicFee(baseFee, degree);
        assertTrue(dynamic > baseFee, "Fee should increase for high degree");
    }

    function testDynamicFee_CappedAtMax() public pure {
        uint24 baseFee = 3000;
        uint256 degree = SwapMath.MAX_SWAP_FEE + 1;
        uint24 dynamic = SwapMath.dynamicFee(baseFee, degree);
        assertEq(dynamic, SwapMath.MAX_SWAP_FEE - 10000, "Fee should be capped");
    }

    // =========================================
    // getAmountOut Tests
    // =========================================

    function testGetAmountOut_FixedFee() public view {
        uint256 amountIn = 100e18;
        uint24 fee = 3000; // 0.3%
        (uint256 amountOut, uint256 feeAmount) = SwapMath.getAmountOut(testReserves, fee, true, amountIn);

        (uint256 amountInWithoutFee, uint256 expectedFeeAmount) = fee.deduct(amountIn);
        assertEq(feeAmount, expectedFeeAmount, "Fee amount should be correct");

        uint256 expectedAmountOut = (amountInWithoutFee * 1000e18) / (1000e18 + amountInWithoutFee);
        assertEq(amountOut, expectedAmountOut);
    }

    function testGetAmountOut_DynamicFee() public view {
        uint256 amountIn = 100e18;
        uint24 baseFee = 3000; // 0.3%
        (uint256 amountOut, uint24 finalFee,) =
            SwapMath.getAmountOut(testReserves, testTruncatedReserves, baseFee, true, amountIn);
        assertTrue(finalFee > baseFee, "Dynamic fee should be higher than base fee");

        (uint256 expectedAmountOutFixed,) = SwapMath.getAmountOut(testReserves, baseFee, true, amountIn);
        assertTrue(amountOut < expectedAmountOutFixed, "Amount out with dynamic fee should be less than with fixed fee");
    }

    // =========================================
    // getAmountIn Tests
    // =========================================

    function testGetAmountIn_FixedFee() public view {
        uint256 amountOut = 100e18;
        uint24 fee = 3000; // 0.3%
        (uint256 amountIn, uint256 feeAmount) = SwapMath.getAmountIn(testReserves, fee, true, amountOut);

        uint256 expectedAmountInWithoutFee = (1000e18 * amountOut) / (1000e18 - amountOut) + 1;
        uint256 expectedAmountIn = (expectedAmountInWithoutFee * 1e6 + (1e6 - fee - 1)) / (1e6 - fee);
        uint256 expectedFeeAmount = expectedAmountIn - expectedAmountInWithoutFee;

        assertEq(amountIn, expectedAmountIn, "Amount in should be correct");
        assertEq(feeAmount, expectedFeeAmount, "Fee amount should be correct");
    }

    function testGetAmountIn_DynamicFee() public view {
        uint256 amountOut = 100e18;
        uint24 baseFee = 3000; // 0.3%
        (uint256 amountIn, uint24 finalFee,) =
            SwapMath.getAmountIn(testReserves, testTruncatedReserves, baseFee, true, amountOut);
        assertTrue(finalFee > baseFee, "Dynamic fee should be higher than base fee");

        (uint256 expectedAmountInFixed,) = SwapMath.getAmountIn(testReserves, baseFee, true, amountOut);
        assertTrue(amountIn > expectedAmountInFixed, "Amount in with dynamic fee should be greater");
    }

    // =========================================
    // getPriceDegree Tests
    // =========================================

    function testGetPriceDegree_AmountIn() public view {
        uint256 amountIn = 100e18;
        uint24 lpFee = 3000;
        uint256 degree = SwapMath.getPriceDegree(testReserves, testTruncatedReserves, lpFee, true, amountIn, 0);
        assertTrue(degree > 0, "Degree should be positive for a swap");
    }

    function testGetPriceDegree_AmountOut() public view {
        uint256 amountOut = 100e18;
        uint24 lpFee = 3000;
        uint256 degree = SwapMath.getPriceDegree(testReserves, testTruncatedReserves, lpFee, true, 0, amountOut);
        assertTrue(degree > 0, "Degree should be positive for a swap");
    }

    function testGetPriceDegree_ZeroForNoSwap() public view {
        uint256 degree = SwapMath.getPriceDegree(testReserves, testTruncatedReserves, 3000, true, 0, 0);
        assertEq(degree, 0, "Degree should be zero for no swap");
    }
}
