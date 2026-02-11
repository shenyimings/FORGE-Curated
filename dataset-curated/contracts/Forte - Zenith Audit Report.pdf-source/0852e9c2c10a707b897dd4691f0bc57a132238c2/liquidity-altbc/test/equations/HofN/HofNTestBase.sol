/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCEquationBase} from "test/equations/ALTBCEquationBase.sol";
import {MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";

/**
 * @title Base Contract for Testing Equation HofN
 * @author  @oscarsernarosero @mpetersoCode55, @VoR0220, @palmerg4, @steveC
 */
contract HofNTestBase is ALTBCEquationBase {
    uint8 constant MAX_TOLERANCE = 1;
    uint8 constant TOLERANCE_PRECISION = 36;
    uint256 constant TOLERANCE_DEN = 10 ** TOLERANCE_PRECISION;
}
