/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {MultiplierTestBase} from "test/equations/Multiplier/MultiplierTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

/**
 * @title Test Math For Multiplier
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract MultiplierFuzzTests is MultiplierTestBase {
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    function testEquations_Multiplier_multiplicationFuzz(uint256 multiplier, uint256 term1) public {
        multiplier = bound(term1, multiplierLower, multiplierUpper);
        term1 = bound(term1, term1Lower, term1Upper);

        packedFloat result = int(multiplier).toPackedFloat(-18).mul(int(term1).toPackedFloat(-36));
        (int solMan, int solExp) = result.decode();

        string[] memory inputs = _buildFFICalculateMultiplier(multiplier, term1, 0);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

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
        console2.log("pye  ", pyMan);
        console2.log("sole ", solExp);
        console2.log("pym  ", pyExp);

        assertTrue(
            areWithinTolerance(uint(solMan < 0 ? solMan * -1 : solMan), uint(pyMan < 0 ? pyMan * -1 : pyMan), MAX_TOLERANCE, TOLERANCE_DEN),
            "mantissa not within tolerance"
        );
        assertEq(solExp, pyExp);
    }

    function testEquations_Multiplier_divisionFuzz(uint256 multiplier, uint256 term1) public {
        multiplier = bound(multiplier, multiplierLower, multiplierUpper);
        term1 = bound(term1, term1Lower, term1Upper);

        packedFloat result = int(term1).toPackedFloat(-36).div(int(multiplier).toPackedFloat(-18));
        (int solMan, int solExp) = result.decode();

        string[] memory inputs = _buildFFICalculateMultiplier(multiplier, term1, 1);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));
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
            console2.log("solm ", solMan);
            console2.log("pye  ", pyMan);
            console2.log("sole ", solExp);
            console2.log("pym  ", pyExp);

            assertTrue(
                areWithinTolerance(uint(solMan < 0 ? solMan * -1 : solMan), uint(pyMan < 0 ? pyMan * -1 : pyMan), MAX_TOLERANCE, TOLERANCE_DEN),
                "mantissa not within tolerance"
            );
            assertEq(solExp, pyExp);
        }
    }
}
