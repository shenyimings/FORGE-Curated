/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, Float, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {MultiplierTestBase} from "test/equations/Multiplier/MultiplierTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Math For Withdraw Multiplier
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract WithdrawMultiplierFuzzTest is MultiplierTestBase {
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using MathLibs for Float;

    function testEquations_WithdrawMultiplierFuzz(uint256 _uj, uint256 _W, uint256 _multiplicand) public {
        _W = bound(_W, Wlower, Wupper);
        _uj = bound(_uj, 1, (_W * 10000) / 9999);
        _multiplicand = bound(_uj, mulLower, mulUpper);

        packedFloat q = int(_uj).toPackedFloat(-18).div(int(_W).toPackedFloat(-18));
        if(q.eq(int(1).toPackedFloat(0))) return;
        packedFloat multiplier = int(1).toPackedFloat(0).sub(q);
        packedFloat multiplicand = int(_multiplicand).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateWithdrawMultiplier(_uj, _W, _multiplicand, 0);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

        packedFloat result = multiplier.mul(multiplicand);
        (int solMan, int solExp) = result.decode();
        if(!checkFractional(result, pyMan, pyExp)) {
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
            if (solMan != 0 && pyMan != 0) assertEq(solExp, pyExp);

            // Check the division case for bn
            inputs = _buildFFICalculateWithdrawMultiplier(_uj, _W, _multiplicand, 1);
            res = vm.ffi(inputs);
            (pyMan, pyExp) = abi.decode((res), (int256, int256));

            result = multiplicand.div(multiplier);
            (solMan, solExp) = result.decode();

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
            if (solMan != 0 && pyMan != 0) assertEq(solExp, pyExp);
        }
    }
}
