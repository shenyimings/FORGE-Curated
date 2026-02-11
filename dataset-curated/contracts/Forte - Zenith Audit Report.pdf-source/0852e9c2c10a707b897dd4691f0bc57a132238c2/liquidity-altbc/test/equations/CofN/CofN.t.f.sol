/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, Float, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {CofNTestBase} from "test/equations/CofN/CofNTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import "lib/liquidity-base/src/common/IErrors.sol";

/**
 * @title Test Math For c of n
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract CofNFuzzTests is CofNTestBase {
    using ALTBCEquations for ALTBCDef;
    using ALTBCEquations for packedFloat;
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using MathLibs for Float;

    /**
     * @dev test for calculation of c of n.
     * @notice some or all of the parameters are expected to be in WADs, and therefore the Python math should take this into account
     * @param _Bn fuzzed variable. Expected in WADs
     * @param _OldBn fuzzed variable. Expected in WADs
     * @param _Xn fuzzed variable. Naturally in WADs
     * @param _Cn fuzzed variable. Expected in WADs
     * @notice this test shows a few interesing bounds (see also CofNTestBase for bound values):
     * 1. Max supply of a token can never be more than 1e11 * 1e18 or 100 billion tokens (with 18 decimals)
     * 2. The price can't be more than 6.27 * 1e27 y token per each x token in avarage, since this would create eventually
     * an overflow in the math when x approaches its x_upper value. This is because the area under the curve
     * would be more than type(uint192).max value which is the max value found in F(D) test.
     * 3. However, the upper price is restricted even more by the bounds of Sn which makes the former point almost useless.
     * This test shows that Sn can never be more than 10 (1e19 WADs) which means that the relationship between max supply
     * and the difference between upperPrice and lower price can't be less than 0.1, and since maxSupply can't be more than
     * 1e11 * 1e18, this means that the highest upperPrice we could have is 1e12 or a raw upper price of a trillion y tokens
     * for each x token. However, there is no actual restriction since a difference of a trillion tokens betwenn Pupper
     * and Plower could be achieved with an infinite amount of values. Therefore, math alone is not enough foe this bound.
     * In reallity, a upper price of 10 billion is more than enough for us to use as a reasonable bound.
     * 4. Xn should never be less than 1e18 after initialization.
     */
    function testEquations_CofN_CalculateCFuzz(uint256 _Bn, uint256 _OldBn, uint256 _Xn, uint256 _Cn) public {
        _Xn = bound(_Xn, Xlower, Xupper);
        _Bn = bound(_Bn, Blower, Bupper);
        _OldBn = bound(_OldBn, Blower, Bupper);
        _Cn = bound(_Cn, cLower, cUpper);

        altbc.b = int(_Bn).toPackedFloat(-18);
        altbc.c = int(_Cn).toPackedFloat(-18);

        uint solVal;

        string[] memory inputs = _buildFFICalculateC(_Bn, _OldBn, _Xn, _Cn);
        bytes memory res = vm.ffi(inputs);
        (uint256 resUint, uint256 flag) = abi.decode(res, (uint256, uint256));
        console2.log("flag", flag);
        console2.log("python c", resUint);
        if (flag > 0) {
            vm.expectRevert(NegativeValue.selector);
            altbc.calculateCNew(int(_Xn).toPackedFloat(-18), int(_OldBn).toPackedFloat(-18));
            return;
        } else {
            altbc.calculateCNew(int(_Xn).toPackedFloat(-18), int(_OldBn).toPackedFloat(-18));
        }
        solVal = uint(altbc.c.convertpackedFloatToWAD());
        console2.log("Solidity return val: ", solVal);

        console2.log("Python return val: ", resUint);
        Float memory flo = int(solVal).toFloat(-18);
        Float memory pyFlo = int(resUint).toFloat(-18);
        if (!checkFractional(flo.convertToPackedFloat(), pyFlo.mantissa, pyFlo.exponent)) {
            // Perfect precision but off by 1 in certain cases
            assertTrue(
                areWithinTolerance(
                    uint(flo.mantissa < 0 ? flo.mantissa * -1 : flo.mantissa),
                    uint(pyFlo.mantissa < 0 ? pyFlo.mantissa * -1 : pyFlo.mantissa),
                    MAX_TOLERANCE,
                    TOLERANCE_DEN
                ),
                "mantissa not within tolerance"
            );
        }
    }
}
