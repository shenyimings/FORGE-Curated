// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
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

    function testEquations_WithdrawMultiplierFuzz(uint256 _uj, uint256 _W, uint256 _multiplicand) public {
        _W = bound(_W, Wlower, Wupper);
        _uj = bound(_uj, 1, (_W * 10000) / 9999);
        _multiplicand = bound(_uj, mulLower, mulUpper);

        packedFloat q = int(_uj).toPackedFloat(-18).div(int(_W).toPackedFloat(-18));
        if (q.eq(int(1).toPackedFloat(0))) return;
        packedFloat multiplier = int(1).toPackedFloat(0).sub(q);
        packedFloat multiplicand = int(_multiplicand).toPackedFloat(-18);

        string[] memory inputs = _buildFFICalculateWithdrawMultiplier(_uj, _W, _multiplicand, 0);
        bytes memory res = vm.ffi(inputs);
        (int pyMan, int pyExp) = abi.decode((res), (int256, int256));

        packedFloat result = multiplier.mul(multiplicand);
        assertTrue(
            areWithinTolerance(
                result,
                (pyMan).toPackedFloat(pyExp),
                int(uint(MAX_TOLERANCE)).toPackedFloat(-int(uint(TOLERANCE_PRECISION)))
            ),
            "mantissa not within tolerance"
        );

        // Check the division case for bn
        inputs = _buildFFICalculateWithdrawMultiplier(_uj, _W, _multiplicand, 1);
        res = vm.ffi(inputs);
        (pyMan, pyExp) = abi.decode((res), (int256, int256));

        result = multiplicand.div(multiplier);
        assertTrue(
            areWithinTolerance(
                result,
                (pyMan).toPackedFloat(pyExp),
                int(uint(MAX_TOLERANCE)).toPackedFloat(-int(uint(TOLERANCE_PRECISION)))
            ),
            "mantissa not within tolerance"
        );
    }
}
