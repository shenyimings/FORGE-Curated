// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {packedFloat, MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
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
    using MathLibs for packedFloat;

    function testMathLibs_FloatLibCannotOverFlow_packedFloat() public pure {
        packedFloat a = int(1e40).toPackedFloat(0);
        packedFloat r = a.mul(a);
        (int rMan, int rExp) = r.decode();
        console2.log(rMan);
        console2.log(rExp);
        assertEq(rMan, int(1e71));
        assertEq(rExp, int(9));
    }

    function testMathLibs_FloatLibCannotUnderFlow_packedFloat() public pure {
        packedFloat a = int(10).toPackedFloat(0);
        packedFloat b = int(20).toPackedFloat(0);
        packedFloat r = a.sub(b);
        (int rMan, int rExp) = r.decode();
        assertEq(rMan, int(-1e37));
        assertEq(rExp, int(-36));
    }

    function testMathLibs_convertpackedFloatToSpecificDecimals_negativeInputAlwaysZero(
        int256 _inputMan,
        int256 _inputExp,
        uint256 _decimals
    ) public pure {
        int exp = bound(_inputExp, -38, 0);
        _decimals = bound(_decimals, 1, 18);
        // -1e50 is the smallest number that would consistently not panic when reaching | result = mantissa / int(10 ** diff) | in convertpackedFloatToSpecificDecimals
        int negativeMan = bound(_inputMan, -1e50, 0);
        console2.log(type(int256).min);
        packedFloat negValue = negativeMan.toPackedFloat(exp);
        int result = negValue.convertpackedFloatToSpecificDecimals(int(_decimals));
        assertTrue(result <= 0);
    }
}
