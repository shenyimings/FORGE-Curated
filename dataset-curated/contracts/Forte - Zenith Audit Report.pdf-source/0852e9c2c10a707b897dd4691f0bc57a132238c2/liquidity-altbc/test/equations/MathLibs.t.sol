/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {packedFloat, Float, MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";

/**
 * @title Math Dependency Test
 * @dev this will tell us when our math libraries change in a way where we might need to add
 * unit tests for our equation among other things.
 * @author @oscarsernarosero @cirsteve
 */
contract MAthLibsTest is Test {
    using MathLibs for int256;
    using MathLibs for Float;
    using MathLibs for packedFloat;

    function testMathLibs_FloatLibCannotOverFlow_packedFloat() public pure {
        packedFloat a = int(1e40).toPackedFloat(0);
        packedFloat r = a.mul(a);
        (int rMan, int rExp) = r.decode();
        assertEq(rMan, int(1e37));
        assertEq(rExp, int(43));
    }

    function testMathLibs_FloatLibCannotOverFlow_Float() public pure {
        Float memory a = int(1e37).toFloat(0);
        Float memory r = a.mul(a).mul(a);
        int rMan = r.mantissa;
        int rExp = r.exponent;
        assertEq(rMan, int(1e37));
        assertEq(rExp, int(74));
    }

    function testMathLibs_FloatLibCannotUnderFlow_packedFloat() public pure {
        packedFloat a = int(10).toPackedFloat(0);
        packedFloat b = int(20).toPackedFloat(0);
        packedFloat r = a.sub(b);
        (int rMan, int rExp) = r.decode();
        assertEq(rMan, int(-1e37));
        assertEq(rExp, int(-36));
    }

    function testMathLibs_FloatLibCannotUnderFlow_Float() public pure {
        Float memory a = int(10).toFloat(0);
        Float memory b = int(20).toFloat(0);
        Float memory r = a.sub(b);
        int rMan = r.mantissa;
        int rExp = r.exponent;
        assertEq(rMan, int(-1e37));
        assertEq(rExp, int(-36));
    }
}
