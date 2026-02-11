/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {MathLibs, Float, packedFloat} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {LastRevenueClaimTestBase} from "test/equations/LastRevenueClaim/LastRevenueClaimTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Equation Last Revenue Claim
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract LastRevenueClaimFuzzTests is LastRevenueClaimTestBase {
    using MathLibs for uint256;
    using MathLibs for int256;
    using ALTBCEquations for ALTBCDef;
    using ALTBCEquations for packedFloat;
    using MathLibs for packedFloat;

    function testEquations_LastRevenueClaim_CalculateLastRevenueClaim(
        uint256 _h,
        uint256 _W,
        uint256 _W_hat,
        uint256 _R_hat,
        uint256 q
    ) public {
        _h = bound(_h, hLower, hUpper);
        _W = bound(_W, Wlower, Wupper);
        _W_hat = bound(_W_hat, Wlower, _W);
        _R_hat = bound(_R_hat, 0, _W);
        q = bound(q, Xlower, Xupper);
        uint256 wj = q * _W;
        string[] memory inputs = _buildFIICalculateLastRevenueClaim(_h, wj, _W_hat, _R_hat);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

        packedFloat hnFloat = int(_h).toPackedFloat(-18);
        packedFloat wjFloat = int(wj).toPackedFloat(-18);
        packedFloat wHatFloat = int(_W_hat).toPackedFloat(-18);
        packedFloat rHatFloat = int(_R_hat).toPackedFloat(-18);

        packedFloat solVal = ALTBCEquations.calculateLastRevenueClaim(hnFloat, wjFloat, wHatFloat, rHatFloat);
        (int solMan, int solExp) = solVal.decode();
        if (!checkFractional(solVal, pyMan, pyExp)) {
            if (pyMan == 0 && solMan == 0) return;
            if (pyExp != solExp) {
                if (pyExp > solExp) {
                    ++solExp;
                    solMan /= 10;
                } else {
                    ++pyExp;
                    pyMan /= 10;
                }
            }
            console2.log("solm ", solMan);
            console2.log("sole ", solExp);
            console2.log("pym  ", pyMan);
            console2.log("pye  ", pyExp);
            assertTrue(
                areWithinTolerance(
                    uint(solMan < 0 ? solMan * -1 : solMan),
                    uint(pyMan < 0 ? pyMan * -1 : pyMan),
                    MAX_TOLERANCE,
                    TOLERANCE_DEN
                ),
                "mantissa not within tolerance"
            );
            assertEq(solExp, pyExp);
        }
    }
}
