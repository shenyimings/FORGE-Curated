// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCEquationBase} from "test/equations/ALTBCEquationBase.sol";
import {MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";

/**
 * @title Base Contract for Testing Equation Dn
 * @author  @oscarsernarosero @mpetersoCode55
 */
contract DnTestBase is ALTBCEquationBase {
    uint8 constant MAX_TOLERANCE = 1;
    uint8 constant TOLERANCE_PRECISION = 36;
    uint256 constant TOLERANCE_DEN = 10 ** TOLERANCE_PRECISION;
}
