/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import {ALTBCEquationBase} from "test/equations/ALTBCEquationBase.sol";

/**
 * @title Test Math For Beta
 * @dev Test base for Beta. Used for bounding input variables in unit and fuzz test for Beta.
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract QofMTestBase is ALTBCEquationBase {
    using ALTBCEquations for ALTBCDef;

    uint8 constant MAX_TOLERANCE = 1;
    uint8 constant TOLERANCE_PRECISION = 36;
    uint256 constant TOLERANCE_DEN = 10 ** TOLERANCE_PRECISION;
}
