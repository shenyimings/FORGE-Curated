/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCEquationBase} from "test/equations/ALTBCEquationBase.sol";
import {MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";

/**
 * @title Base Contract for Testing Equation Multiplier
 * @author  @oscarsernarosero @mpetersoCode55
 */
contract MultiplierTestBase is ALTBCEquationBase {
    uint256 constant mulLower = 1;
    uint256 constant mulUpper = MathLibs.WAD * 2;
    uint256 constant multiplierLower = MathLibs.WAD;
    uint256 constant multiplierUpper = 2 * MathLibs.WAD;
    uint256 constant term1Lower = MathLibs.WAD;
    uint256 constant term1Upper = MathLibs.WAD ** 3;
    uint8 constant MAX_TOLERANCE = 1;
    uint8 constant TOLERANCE_PRECISION = 32;
    uint256 constant TOLERANCE_DEN = 10 ** TOLERANCE_PRECISION;
}
