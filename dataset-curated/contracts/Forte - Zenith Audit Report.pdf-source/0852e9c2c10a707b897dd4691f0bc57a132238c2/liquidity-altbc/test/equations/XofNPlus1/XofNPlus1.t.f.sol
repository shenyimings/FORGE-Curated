/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, Float, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {XofNPlus1TestBase} from "test/equations/XofNPlus1/XofNPlus1TestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Math For x of n+1
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract XofNPlus1FuzzTests is XofNPlus1TestBase {
    using ALTBCEquations for ALTBCDef;
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    function testEquations_XofNPlus1_CalculateFuzz(uint256 Dn, uint b, uint256 cn, uint256 Xn) public {
        Dn = bound(Dn, Dlower, Dupper);
        b = bound(b, Blower, Bupper);
        cn = bound(cn, cLower, cUpper);
        Xn = bound(Xn, Xlower, Xupper);

        altbc.b = int(b).toPackedFloat(-18);
        altbc.c = int(cn).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateXofNPlus1(b, cn, Dn);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

        packedFloat solVal = altbc.calculateXofNPlus1(int(Dn).toPackedFloat(-18));
        (int solMan, int solExp) = solVal.decode();
        if(!checkFractional(solVal, pyMan, pyExp)) {
            if (pyExp != solExp) {
                if (pyExp > solExp) {
                    ++solExp;
                    solMan /= 10;
                } else {
                    ++pyExp;
                    pyMan /= 10;
                }
            }

            assertTrue(
                areWithinTolerance(uint(solMan < 0 ? solMan * -1 : solMan), uint(pyMan < 0 ? pyMan * -1 : pyMan), MAX_TOLERANCE, TOLERANCE_DEN),
                "mantissa not within tolerance"
            );
            assertEq(solExp, pyExp);
        }
    }
}
