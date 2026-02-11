// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {BofNTestBase} from "test/equations/BofN/BofNTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Math For c of n
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 * @notice c of n can never be more than pLower, c of n can be more than 1.
 */
contract BofNFuzzTests is BofNTestBase {
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using ALTBCEquations for ALTBCDef;

    /**
     * @dev test for calculation of c of n.
     * @notice some or all of the parameters are expected to be in WADs, and therefore the Python math should take this into account
     * @param _Xn fuzzed variable. Naturally in WADs
     * @param _C fuzzed variable. Expected in WADs
     * @notice the bounds for _C (see BofNTestBase.sol):
     * Lower bound: _C is assumed to not be less than 0.1 (in WADs) since that would mean either an exorbitant market capitalization of the pool,
     * or a token with a very steep price curve due to a low supply and very apart price boundaries
     * Upper bound: _C can never be more than a WAD because this would make Sn be 0 (Sn = 1/_C). Since _C is expected to be a WAD, this means that
     * the upper bound for _C is theoretically WAD * WAD, but due to Solidity rounding strategy, this number is actually (WAD * WAD) / 2, or
     * (WAD * WAD) / 2.
     */
    function testEquations_BofNFuzz_CalculateBofNFuzz(uint256 _Xn, uint256 _C, uint256 _V) public {
        _Xn = bound(_Xn, Xlower, Xupper);
        _C = bound(_C, CapitalClower, CapitalCupper);
        _V = bound(_V, Vlower, Vupper);

        altbc.C = int(_C).toPackedFloat(-18);
        altbc.V = int(_V).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateBn(_Xn, _C, _V);
        bytes memory res = vm.ffi(inputs);

        altbc.calculateBn(int(_Xn).toPackedFloat(-18));
        packedFloat solVal = altbc.b;
        (int solMan, int solExp) = solVal.decode();
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));
        if (!checkFractional(solVal, pyMan, pyExp)) {
            while (pyExp != solExp) {
                if (pyExp > solExp) {
                    ++solExp;
                    solMan /= 10;
                } else {
                    ++pyExp;
                    pyMan /= 10;
                }
            }

            assertEq(solMan, pyMan);
            assertEq(solExp, pyExp);
        }
    }
}
