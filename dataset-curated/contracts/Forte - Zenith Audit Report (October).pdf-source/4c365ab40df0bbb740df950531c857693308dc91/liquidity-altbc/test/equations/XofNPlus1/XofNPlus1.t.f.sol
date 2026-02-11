// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
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

        console2.log("b", b);
        console2.log("cn", cn);
        console2.log("Dn", Dn);
        console2.log("Xn", Xn);
        console2.log("before equation calc");
        packedFloat solVal = altbc.calculateXofNPlus1(int(Dn).toPackedFloat(-18));

        console2.log("before tolerance check");
        assertTrue(
            areWithinTolerance(
                solVal,
                (pyMan).toPackedFloat(pyExp),
                int(uint(MAX_TOLERANCE)).toPackedFloat(-int(uint(TOLERANCE_PRECISION)))
            ),
            "mantissa not within tolerance"
        );
    }
}
