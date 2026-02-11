// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {packedFloat} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";

/**
 * @title TBC Data Structures
 * @dev All TBC definitions can be found here.
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

/// ALTBC

struct ALTBCDef {
    packedFloat b;
    packedFloat c;
    packedFloat C;
    packedFloat xMin;
    packedFloat xMax;
    packedFloat V;
    packedFloat Zn;
}

struct ALTBCInput {
    uint256 _lowerPrice;
    uint256 _wInactive;
    uint256 _V;
    uint256 _xMin;
    uint256 _C;
}
