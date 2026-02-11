/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, Float, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {priceEquationTestBase} from "test/equations/priceEquation/priceEquationTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Equation f(x)
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract priceEquationFuzzTests is priceEquationTestBase {
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using ALTBCEquations for uint256;
    using ALTBCEquations for ALTBCDef;

    /**
     * @dev test for calculation of f of x.
     * @notice some or all of the parameters are expected to be in WADs, and therefore the Python math should take this into account
     * @param _Xn fuzzed variable. Expected in WADs
     * @param _Bn fuzzed variable. Expected in WADs
     * @param _Cn fuzzed variable. Expected in WADs
     * @notice the bounds (see FinverseTestBase.sol):
     * 1. Cn can be as low as 1e-18 and as high as 1e20 * WAD.
     * 2. Bn: 0 < Bn < 10 (in WADs)
     * 3. _Xn: can go from 1 token (1 * WAD) and 100 billion tokens (1e11 * WADs)
     */
    function testEquations_priceEquationFuzz_CalculatepriceEquationFuzz(uint256 _Xn, uint256 _Bn, uint256 _Cn) public {
        _Cn = bound(_Cn, cLower, cUpper);
        _Bn = bound(_Bn, Blower, Bupper);
        _Xn = bound(_Xn, Xlower, Xupper);

        altbc.c = int(_Cn).toPackedFloat(-36);
        altbc.b = int(_Bn).toPackedFloat(-36);

        string[] memory inputs = _buildFFICalculatePriceEquation(_Xn, _Bn, _Cn);
        bytes memory res = vm.ffi(inputs);

        packedFloat solVal = altbc.calculatefx(int(_Xn).toPackedFloat(-18));
        (int solMan, int solExp) = solVal.decode();
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));
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
            // we could be off by one due to rounding issues. The error should be less than 1/1e76
            assertTrue(
                areWithinTolerance(uint(solMan < 0 ? solMan * -1 : solMan), uint(pyMan < 0 ? pyMan * -1 : pyMan), MAX_TOLERANCE, TOLERANCE_DEN),
                "mantissa not within tolerance"
            );

            console2.log("solMan: ", solMan);
            console2.log("solExp: ", solExp);
            console2.log("pyMan: ", pyMan);
            console2.log("pyExp: ", pyExp);
            assertEq(solExp, pyExp);
        }
    }
}
