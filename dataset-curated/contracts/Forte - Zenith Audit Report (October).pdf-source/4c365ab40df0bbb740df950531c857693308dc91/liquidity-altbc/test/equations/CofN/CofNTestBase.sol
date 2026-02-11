// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCEquationBase} from "test/equations/ALTBCEquationBase.sol";
import {MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";

/**
 * @title Test Math For c of n
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55
 */
contract CofNTestBase is ALTBCEquationBase {
    uint8 constant MAX_TOLERANCE = 5;
    uint8 constant TOLERANCE_PRECISION = 36;
    uint256 constant TOLERANCE_DEN = 10 ** TOLERANCE_PRECISION;
    int constant MAX_ABSOLUTE_ERROR_MAN = 1;
    int constant MAX_ABSOLUTE_ERROR_EXP = -36;
}
