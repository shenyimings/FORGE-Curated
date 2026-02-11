/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {MathLibs, packedFloat} from "src/amm/mathLibs/MathLibs.sol";
import {TestCommon} from "test/util/TestCommon.sol";

/**
 * @title Test Math Library
 * @dev tests the limits of the math library to better understand what can be done what cannot.
 * @author @oscarsernarosero @mpetersoCode55
 */
contract MathLibTests is TestCommon {
    using MathLibs for uint256;
    using MathLibs for packedFloat;
    using MathLibs for int256;

    uint one = 1;
    uint two = 2;
    uint max256 = 2 ** 256 - 1;
    uint max256Sub1 = 2 ** 256 - 2;

    /**
     * @dev this test is just an informational test
     * @notice 340282366920938463463374607431768211456 is the number at which the sqr starts overflowing
     */
    function testEquation_MathLibTests_MaxSquareableNumberPureSol() public {
        uint maxSqr = 340_282_366_920_938_463_463_374607431768211455;
        maxSqr * maxSqr;
        vm.expectRevert();
        (maxSqr + 1) * (maxSqr + 1);
    }

    function testEquations_MathLibTests_NaturalLogarithmWAD2(uint256 x) public {
        x = bound(x, 1, 1e36);

        string[] memory inputs = _buildFFICalculateLogarithmNaturalWAD2(x);
        bytes memory res = vm.ffi(inputs);
        int pyVal = abi.decode(res, (int256));
        uint resUint = uint(-pyVal);

        uint256 solVal = x.lnWAD2Negative();
        console2.log("returnValLo: ", solVal);

        console2.log("Res: ", resUint);
        if (!areWithinTolerance(resUint, solVal, 1, 1e27)) {
            revert("out of tolerance");
        }
    }

    function testconvertpackedFloatToWADPositive() public pure {
        int256 manA = 2000;
        int256 expA = -16;
        packedFloat floA = manA.toPackedFloat(expA);

        int256 result = MathLibs.convertpackedFloatToWAD(floA);
        console2.log(result);
        assertEq(200000, result);
    }

    function testconvertpackedFloatToWADNegative() public pure {
        int256 manA = 2000;
        int256 expA = -20;
        packedFloat floA = manA.toPackedFloat(expA);

        int256 result = MathLibs.convertpackedFloatToWAD(floA);
        console2.log(result);
        assertEq(20, result);
    }

    function testconvertpackedFloatToDoubleWADPositive() public pure {
        int256 manA = 2000;
        int256 expA = -34;
        packedFloat floA = manA.toPackedFloat(expA);

        int256 result = MathLibs.convertpackedFloatToDoubleWAD(floA);
        console2.log(result);
        assertEq(200000, result);
    }

    function testconvertpackedFloatToDoubleWADNegative() public pure {
        int256 manA = 2000;
        int256 expA = -38;
        packedFloat floA = manA.toPackedFloat(expA);

        int256 result = MathLibs.convertpackedFloatToDoubleWAD(floA);
        console2.log(result);
        assertEq(20, result);
    }
}
