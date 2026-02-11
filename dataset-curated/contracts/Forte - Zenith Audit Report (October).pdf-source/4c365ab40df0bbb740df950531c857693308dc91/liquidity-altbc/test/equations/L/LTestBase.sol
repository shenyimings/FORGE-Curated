// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCEquationBase} from "test/equations/ALTBCEquationBase.sol";
import {MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";

/**
 * @title Test Math For L
 * @dev fuzz test that compares Solidity results against the same math in Python
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @Palmerg4 @VoR0220
 */
contract LTestBase is ALTBCEquationBase {
    uint8 constant MAX_TOLERANCE = 1;
    uint8 constant TOLERANCE_PRECISION = 34;
    uint256 constant TOLERANCE_DEN = 10 ** TOLERANCE_PRECISION;
}
