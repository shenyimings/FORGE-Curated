// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {QofMTestBase} from "test/equations/QofM/QofMTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Equation q
 * @author  @oscarsernarosero @cirsteve @Palmerg4
 */

struct Q {
    int aMan;
    int aExp;
    int bMan;
    int bExp;
    int qMan;
    int qExp;
}
contract QofMFuzzTests is QofMTestBase {
    using ALTBCEquations for ALTBCDef;
    using ALTBCEquations for packedFloat;
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    function testEquations_QofMFuzz_CalculateQofMFuzz(uint256 _Xn, uint256 _xMax, uint256 _L, uint _Dn, uint256 _A, uint256 _B) public {
        _Xn = bound(_Xn, Xlower, Xupper);
        _xMax = bound(_xMax, _Xn + 1, _Xn * 1e6);
        _L = bound(_L, Llower, Lupper);
        _Dn = bound(_Dn, Dlower, Dupper);
        _A = bound(_A, 0, _Xn);
        _B = bound(_B, 0, _Xn);
        if (_A == 0 && _B == 0) {
            _A = 1000000000;
        }
        Q memory q;

        {
            string[] memory inputs = _buildFFICalculateQofM(_A, _B, _L, _xMax, _Xn, _Dn);
            bytes memory res = vm.ffi(inputs);
            (q.aExp, q.aMan, q.bExp, q.bMan, q.qExp, q.qMan) = abi.decode(res, (int256, int256, int256, int256, int256, int256));

            console2.log("pyAMan ", q.aMan);
            console2.log("pyAExp ", q.aExp);
            console2.log("pyBMan ", q.bMan);
            console2.log("pyBExp ", q.bExp);
            console2.log("pyQMan ", q.qMan);
            console2.log("pyQExp ", q.qExp);
        }
        packedFloat solA;
        packedFloat solB;
        packedFloat solQ;
        {
            altbc.xMax = int(_xMax).toPackedFloat(-18);
            packedFloat Xn = int(_Xn).toPackedFloat(-18);
            packedFloat L = int(_L).toPackedFloat(-18);
            packedFloat Dn = int(_Dn).toPackedFloat(-18);
            packedFloat A = int(_A).toPackedFloat(-18);
            packedFloat B = int(_B).toPackedFloat(-18);
            (solA, solB, solQ) = altbc.calculateQ(Xn, A, B, L, Dn);
        }

        (int solAMan, int solAExp) = solA.decode();
        (int solBMan, int solBExp) = solB.decode();
        (int solQMan, int solQExp) = solQ.decode();
        if (!checkFractional(solA, q.aMan, q.aExp)) {
            while (q.aExp != solAExp) {
                if (q.aExp > solAExp) {
                    ++solAExp;
                    solAMan /= 10;
                } else {
                    ++q.aExp;
                    q.aMan /= 10;
                }
            }
            assertTrue(
                areWithinTolerance(
                    uint(solAMan < 0 ? solAMan * -1 : solAMan),
                    uint(q.aMan < 0 ? q.aMan * -1 : q.aMan),
                    MAX_TOLERANCE,
                    TOLERANCE_PRECISION
                ),
                "a mantissa out of tolerance"
            );
            if (q.aMan != 0) assertEq(solAExp, q.aExp, "a exponent different");
        }
        if (!checkFractional(solB, q.bMan, q.bExp)) {
            while (q.bExp != solBExp) {
                if (q.bExp > solBExp) {
                    ++solBExp;
                    solBMan /= 10;
                } else {
                    ++q.bExp;
                    q.bMan /= 10;
                }
            }
            assertTrue(
                areWithinTolerance(
                    uint(solBMan < 0 ? solBMan * -1 : solBMan),
                    uint(q.bMan < 0 ? q.bMan * -1 : q.bMan),
                    MAX_TOLERANCE,
                    TOLERANCE_PRECISION
                ),
                "b mantissa out of tolerance"
            );
            if (q.bMan != 0) assertEq(solBExp, q.bExp, "b exponent different");
        }
        if (!checkFractional(solQ, q.qMan, q.qExp)) {
            while (q.qExp != solQExp) {
                if (q.qExp > solQExp) {
                    ++solQExp;
                    solQMan /= 10;
                } else {
                    ++q.qExp;
                    q.qMan /= 10;
                }
            }
            assertTrue(
                areWithinTolerance(
                    uint(solQMan < 0 ? solQMan * -1 : solQMan),
                    uint(q.qMan < 0 ? q.qMan * -1 : q.qMan),
                    MAX_TOLERANCE,
                    TOLERANCE_PRECISION
                ),
                "q mantissa out of tolerance"
            );
            if (q.qMan != 0) assertEq(solQExp, q.qExp, "q exponent different");
        }
    }
}
