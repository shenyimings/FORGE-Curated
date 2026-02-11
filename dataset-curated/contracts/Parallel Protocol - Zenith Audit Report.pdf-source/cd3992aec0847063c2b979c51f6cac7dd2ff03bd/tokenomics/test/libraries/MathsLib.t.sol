// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

import "@forge-std/Test.sol";

import "contracts/libraries/MathsLib.sol";

contract MathsLib_Test is Test {
    using MathsLib for uint256;

    function test_MathsLib_MulDivDown(uint256 x, uint256 y, uint256 denominator) external {
        // Ignore cases where x * y overflows or denominator is 0.
        unchecked {
            if (denominator == 0 || (x != 0 && (x * y) / x != y)) return;
        }

        assertEq(MathsLib.mulDivDown(x, y, denominator), (x * y) / denominator);
    }

    function test_MathsLib_MulDivDown_RevertWhen_Overflow(uint256 x, uint256 y, uint256 denominator) external {
        denominator = bound(denominator, 1, type(uint256).max);
        // Overflow if
        //     x * y > type(uint256).max
        // <=> y > 0 and x > type(uint256).max / y
        // With
        //     type(uint256).max / y < type(uint256).max
        // <=> y > 1
        y = bound(y, 2, type(uint256).max);
        x = bound(x, type(uint256).max / y + 1, type(uint256).max);

        vm.expectRevert();
        MathsLib.mulDivDown(x, y, denominator);
    }

    function test_MathsLib_MulDivDown_RevertWhen_ZeroDenominator(uint256 x, uint256 y) external {
        vm.expectRevert();
        MathsLib.mulDivDown(x, y, 0);
    }

    function test_MathsLib_MulDivUp(uint256 x, uint256 y, uint256 denominator) external {
        denominator = bound(denominator, 1, type(uint256).max - 1);
        y = bound(y, 1, type(uint256).max);
        x = bound(x, 0, (type(uint256).max - denominator - 1) / y);

        assertEq(MathsLib.mulDivUp(x, y, denominator), x * y == 0 ? 0 : (x * y - 1) / denominator + 1);
    }

    function test_MathsLib_MulDivUp_RevertWhen_Overflow(uint256 x, uint256 y, uint256 denominator) external {
        denominator = bound(denominator, 1, type(uint256).max);
        // Overflow if
        //     x * y + denominator - 1 > type(uint256).max
        // <=> x * y > type(uint256).max - denominator + 1
        // <=> y > 0 and x > (type(uint256).max - denominator + 1) / y
        // With
        //     (type(uint256).max - denominator + 1) / y < type(uint256).max
        // <=> y > (type(uint256).max - denominator + 1) / type(uint256).max
        y = bound(y, (type(uint256).max - denominator + 1) / type(uint256).max + 1, type(uint256).max);
        x = bound(x, (type(uint256).max - denominator + 1) / y + 1, type(uint256).max);

        vm.expectRevert();
        MathsLib.mulDivUp(x, y, denominator);
    }

    function test_MathsLib_MulDivUp_RevertWhen_Underverflow(uint256 x, uint256 y) external {
        vm.assume(x > 0 && y > 0);

        vm.expectRevert();
        MathsLib.mulDivUp(x, y, 0);
    }

    function test_MathsLib_MulDivUp_RevertWhen_ZeroDenominator(uint256 x, uint256 y) external {
        vm.expectRevert();
        MathsLib.mulDivUp(x, y, 0);
    }
}
