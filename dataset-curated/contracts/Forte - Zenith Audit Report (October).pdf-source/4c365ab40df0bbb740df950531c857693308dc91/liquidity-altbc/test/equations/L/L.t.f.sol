// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {LTestBase} from "test/equations/L/LTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Math For L
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @Palmerg4 @VoR0220
 */
contract LFuzzTests is LTestBase {
    using ALTBCEquations for ALTBCDef;
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    function testEquations_L_CalculateFuzz(uint256 _xMin, uint256 _V, uint256 _b, uint256 _c, uint _Xn, uint256 _C) public {
        _V = bound(_V, Vlower, Vupper);
        _c = bound(_c, cLower, cUpper);
        _C = bound(_C, CapitalClower, CapitalCupper);
        _Xn = bound(_Xn, Xlower + 1, Xupper);
        _xMin = bound(_xMin, 1, _Xn - 1);
        _b = bound(_b, Blower, Bupper);

        if (_xMin >= _Xn) {
            _xMin = _Xn / 100;
        }

        altbc.V = int(_V).toPackedFloat(-18);
        altbc.xMin = int(_xMin).toPackedFloat(-18);
        altbc.b = int(_b).toPackedFloat(-18);
        altbc.c = int(_c).toPackedFloat(-18);
        altbc.C = int(_C).toPackedFloat(-18);
        packedFloat Xn = int(_Xn).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateL(_xMin, _V, _b, _c, _C, _Xn);
        bytes memory res = vm.ffi(inputs);

        packedFloat solVal = altbc.calculateL(Xn);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

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
