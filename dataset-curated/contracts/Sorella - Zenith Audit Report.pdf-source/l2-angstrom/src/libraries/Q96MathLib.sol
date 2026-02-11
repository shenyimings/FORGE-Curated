// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

/// @author philogy <https://github.com/philogy>
library Q96MathLib {
    uint8 internal constant RESOLUTION = 96;

    function divX96(uint256 x, uint256 y) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDiv(x, 1 << RESOLUTION, y);
    }

    function mulX96(uint256 x, uint256 y) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDivN(x, y, RESOLUTION);
    }
}
