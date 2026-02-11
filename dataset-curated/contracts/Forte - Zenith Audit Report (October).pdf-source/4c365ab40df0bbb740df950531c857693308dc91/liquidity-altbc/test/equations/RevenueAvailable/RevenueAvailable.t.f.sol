// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {MathLibs, packedFloat} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {RevenueAvailableEquationTestBase} from "test/equations/RevenueAvailable/RevenueAvailableEquationBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import {HofNFuzzTests} from "test/equations/HofN/HofN.t.f.sol";

/**
 * @title Test Equation Revenue Available
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract RevenueAvailableFuzzTests is RevenueAvailableEquationTestBase {
    HofNFuzzTests public hnHelper = new HofNFuzzTests();

    using MathLibs for uint256;
    using MathLibs for int256;
    using ALTBCEquations for ALTBCDef;
    using ALTBCEquations for packedFloat;
    using MathLibs for packedFloat;

    function testEquations_RevenueAvailable_CalculateRevenueAvailable(uint256 _wj, uint256 _hn, uint256 _R_hat) public {
        _wj = bound(_wj, Wlower, Wupper);
        _hn = bound(_hn, hLower, hUpper);
        _R_hat = bound(_R_hat, 0, _hn / 2);

        string[] memory inputs = _buildFFICalculateRevenueAvailable(_wj, _hn, _R_hat);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

        packedFloat hnFloat = int(_hn).toPackedFloat(-36);
        packedFloat wjFloat = int(_wj).toPackedFloat(-18);
        packedFloat rHatFloat = int(_R_hat).toPackedFloat(-18);

        packedFloat solVal = wjFloat.calculateRevenueAvailable(hnFloat, rHatFloat);
        if (pyMan == 0 && packedFloat.unwrap(solVal) == 0) return;
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
