/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, Float, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ZofNTestBase} from "test/equations/Zn/ZofNTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Math For Z of n
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract ZofNFuzzTests is ZofNTestBase {
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using ALTBCEquations for ALTBCDef;

    /**
     * @dev test for calculation of Z of n in the case of a liquidity deposit.
     */
    function testEquations_ZofNFuzz_CalculateZofNFuzzDeposit(uint256 _Ln, uint256 _Wn, uint256 _WIn, uint256 _Zn, uint256 _q) public {
        _Wn = bound(_Wn, Wlower, Wupper);
        _WIn = bound(_WIn, Wlower, Wupper);
        _Zn = bound (_Zn, Zlower, Zupper);
        _q = bound(_q, qLower, qUpper);
        _Ln = bound(_Ln, Llower, Lupper);

        if(_Wn == _WIn) {
            _WIn = _WIn - 1;
        }

        if(_Wn < _WIn) {
            return;
        }

        altbc.Zn = int(_Zn).toPackedFloat(-18);
        
        packedFloat Ln = int(_Ln).toPackedFloat(-18);
        packedFloat Wn = int(_Wn).toPackedFloat(-18);
        packedFloat WIn = int(_WIn).toPackedFloat(-18);
        packedFloat q = int(_q).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateZnDeposit( _Ln, _Wn, _WIn, _Zn, _q);
        bytes memory res = vm.ffi(inputs);

        altbc.calculateZ(Ln, Wn, WIn, q, false);
        packedFloat solVal = altbc.Zn;
        Float memory solFloat = solVal.convertToUnpackedFloat();
        int solMan = solFloat.mantissa;
        int solExp = solFloat.exponent;

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

            console2.log(solMan);
            console2.log(pyMan);
            console2.log(solExp);
            console2.log(pyExp);

            assertTrue(
                areWithinTolerance(uint(solMan < 0 ? solMan * -1 : solMan), uint(pyMan < 0 ? pyMan * -1 : pyMan), MAX_TOLERANCE, TOLERANCE_DEN),
                "mantissa not within tolerance"
            );
            assertEq(solExp, pyExp);
        }
    }

    /**
     * @dev test for calculation of Z of n in the case of a withdrawal.
     */
    function testEquations_ZofNFuzz_CalculateZofNWithdrawlFuzz(uint256 _Ln, uint256 _Wn, uint256 _WIn, uint256 _Zn, uint256 _q) public {
        _Wn = bound(_Wn, Wlower, Wupper);
        _WIn = bound(_WIn, Wlower, Wupper);
        _Zn = bound (_Zn, Zlower, Zupper);
        _q = bound(_q, qLower, qUpper);
        _Ln = bound(_Ln, Llower, Lupper);

        if(_Wn == _WIn) {
            _WIn = _WIn - 1;
        }

        if(_Wn < _WIn) {
            return;
        }

        altbc.Zn = int(_Zn).toPackedFloat(-18);
        
        packedFloat Ln = int(_Ln).toPackedFloat(-18);
        packedFloat Wn = int(_Wn).toPackedFloat(-18);
        packedFloat WIn = int(_WIn).toPackedFloat(-18);
        packedFloat q = int(_q).toPackedFloat(-18);

        q = q.mul(float_neg_1);

        string[] memory inputs = _buildFFICalculateZnWithdrawal( _Ln, _Wn, _WIn, _Zn, _q);
        bytes memory res = vm.ffi(inputs);

        altbc.calculateZ(Ln, Wn, WIn, q, false);
        packedFloat solVal = altbc.Zn;
        Float memory solFloat = solVal.convertToUnpackedFloat();
        int solMan = solFloat.mantissa;
        int solExp = solFloat.exponent;

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

            console2.log(solMan);
            console2.log(pyMan);
            console2.log(solExp);
            console2.log(pyExp);
            assertTrue(
                areWithinTolerance(uint(solMan < 0 ? solMan * -1 : solMan), uint(pyMan < 0 ? pyMan * -1 : pyMan), MAX_TOLERANCE, TOLERANCE_DEN),
                "mantissa not within tolerance"
            );
            assertEq(solExp, pyExp);
        }
    }
}
