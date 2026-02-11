// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {DnTestBase} from "test/equations/Dn/DnTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Equation Dn
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract DnFuzzTests is DnTestBase {
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using ALTBCEquations for ALTBCDef;

    /**
     * @dev test for calculation of Dn.
     * @notice some or all of the parameters are expected to be in WADs, and therefore the Python math should take this into account
     * @param _Xn fuzzed variable. Expected in WADs
     * @param _Bn fuzzed variable. Expected in WADs
     * @param _Cn fuzzed variable. Expected in WADs
     * @notice the bounds (see DnTestBase.sol):
     * 1. Cn can be as low as 1e-18 and as high as 1e20 * WAD.
     * 2. Sn: 0 < Sn < 10 (in WADs)
     * 3. _Xn: can go from 1 token (1 * WAD) and 100 billion tokens (1e11 * WADs)
     */
    function testEquations_DnFuzz_CalculateDnFuzz(uint256 _Xn, uint256 _Bn, uint256 _Cn) public {
        _Cn = bound(_Cn, cLower, cUpper);
        _Bn = bound(_Bn, Blower, Bupper);
        _Xn = bound(_Xn, Xlower, Xupper);

        altbc.c = int(_Cn).toPackedFloat(-18);
        altbc.b = int(_Bn).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateDn(_Xn, _Bn, _Cn);
        bytes memory res = vm.ffi(inputs);

        packedFloat solVal = altbc.calculateDn(int(_Xn).toPackedFloat(-18));
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
