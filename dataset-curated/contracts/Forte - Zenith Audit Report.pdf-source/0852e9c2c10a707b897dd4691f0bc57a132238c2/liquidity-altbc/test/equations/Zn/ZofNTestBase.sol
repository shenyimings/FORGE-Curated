/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCEquationBase} from "test/equations/ALTBCEquationBase.sol";
import {MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";

/**
 * @title Test Math For Z of n
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract ZofNTestBase is ALTBCEquationBase {
    uint8 constant MAX_TOLERANCE = 1;
    uint8 constant TOLERANCE_PRECISION = 32;
    uint256 constant TOLERANCE_DEN = 10 ** TOLERANCE_PRECISION;
}