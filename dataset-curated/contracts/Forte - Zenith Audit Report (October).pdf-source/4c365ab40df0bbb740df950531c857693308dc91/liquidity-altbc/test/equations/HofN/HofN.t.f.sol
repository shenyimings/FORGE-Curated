// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {HofNTestBase} from "test/equations/HofN/HofNTestBase.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import "forge-std/console2.sol";
/**
 * @title Test Equation HofN
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract HofNFuzzTests is HofNTestBase {
    using MathLibs for uint256;
    using ALTBCEquations for uint256;
    using ALTBCEquations for ALTBCDef;
    using Strings for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using ALTBCEquations for packedFloat;

    function testEquations_HofNFuzz_CalculateHofNFuzz(uint256 _L, uint256 _W, uint256 _wInactive, uint256 _phi, uint256 _Zn) public {
        _W = bound(_W, Wlower, Wupper);
        _wInactive = bound(_wInactive, Wlower, Wupper);
        _L = bound(_L, Llower, Lupper);
        _phi = bound(_phi, phiLower, phiUpper);
        _Zn = bound(_Zn, Zlower, Zupper);

        if (_W == _wInactive) {
            _wInactive = _wInactive - 1;
        }

        if (_W < _wInactive) {
            return;
        }

        packedFloat W = int(_W).toPackedFloat(-18);
        packedFloat wInactive = int(_wInactive).toPackedFloat(-18);
        packedFloat L = int(_L).toPackedFloat(-18);
        packedFloat phi = int(_phi).toPackedFloat(-18);
        altbc.Zn = int(_Zn).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateHofNFloat(_L, _W, _phi, _Zn, _wInactive);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

        packedFloat solVal = altbc.calculateH(L, W, wInactive, phi);
        (int solMan, int solExp) = solVal.decode();
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
