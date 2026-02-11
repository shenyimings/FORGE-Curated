// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {EquationBase} from "lib/liquidity-base/test/equations/EquationBase.sol";
import {MathLibs, packedFloat} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import {ALTBCPythonUtils} from "test/util/ALTBCPythonUtils.sol";
import "forge-std/console2.sol";

/**
 * @title Test Math For c of n
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract ALTBCEquationBase is EquationBase, ALTBCPythonUtils {
    using MathLibs for int256;
    using MathLibs for packedFloat;

    event PythonReturn(uint256);

    uint256 resUint;

    ALTBCDef altbc;

    uint256 constant Xlower = 1;
    uint256 constant Xupper = MAX_SUPPLY;

    uint256 constant CapitalClower = 1;
    uint256 constant CapitalCupper = (MathLibs.WAD * MathLibs.WAD) / 2;

    uint256 constant cLower = 1;
    uint256 constant cUpper = MathLibs.WAD ** 2;

    uint256 constant Vlower = 1;
    uint256 constant Vupper = 1e23;

    uint256 constant Blower = 1;
    uint256 constant Bupper = (MathLibs.WAD ** 2);

    uint256 constant Dlower = 1;
    uint256 constant Dupper = 1e12 * MathLibs.WAD ** 2;

    uint256 constant PLowerLower = 1_000; // specs: PLower >= 1_000 PMin; PMin > 0 => Lowest PLower = 1_000 * 1
    uint256 constant PLowerUpper = 10_000_000_000 * MathLibs.WAD; // 10 billion dollars

    uint256 public constant XMinLower = Xupper / 1_000_000;
    uint256 public constant XMinUpper = Xupper / 10;

    uint256 constant phiLower = 0;
    uint256 constant phiUpper = MAX_SUPPLY / 10;

    uint256 constant Wlower = 1;
    uint256 constant Wupper = MathLibs.WAD ** 2;

    uint256 constant Llower = 1;
    uint256 constant Lupper = 99 * MathLibs.WAD ** 2;

    uint256 constant hLower = 0;
    uint256 constant hUpper = 9 * 1e37;

    uint256 constant Rlower = 0;
    uint256 constant Rupper = 1e12 * MathLibs.WAD;

    uint256 constant DvUpper = 500095000000000000000000000000000000000000000000000000000;
    uint256 constant DvLower = 1e18 * MathLibs.WAD;

    uint256 qUpper = (MathLibs.WAD ** 2);
    uint256 qLower = 1;

    uint256 Zupper = (MathLibs.WAD ** 2);
    uint256 Zlower = 1;

    packedFloat float_2 = int(2).toPackedFloat(0);
    packedFloat float_1 = int(1).toPackedFloat(0);
    packedFloat float_0 = int(0).toPackedFloat(0);
    packedFloat float_neg_1 = int(-1).toPackedFloat(0);

    function checkFractional(packedFloat solVal, int pyMan, int pyExp) public view returns (bool) {
        packedFloat comparison = solVal;

        if (solVal.lt(float_0)) {
            comparison = comparison.mul(float_neg_1);
        }

        if (comparison.lt(float_1) && comparison.gt(float_0)) {
            (int solMan, int solExp) = solVal.decode();
            while (pyExp != solExp) {
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
                areWithinTolerance(uint(solMan < 0 ? solMan * -1 : solMan), uint(pyMan < 0 ? pyMan * -1 : pyMan), 1, 18),
                "mantissa not within tolerance"
            );
            assertEq(solExp, pyExp);
            return true;
        } else {
            return false;
        }
    }
}
