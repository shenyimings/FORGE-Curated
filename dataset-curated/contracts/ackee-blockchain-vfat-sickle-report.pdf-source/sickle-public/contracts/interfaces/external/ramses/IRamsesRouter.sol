// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IEqualizerRouter } from
    "contracts/interfaces/external/equalizer/IEqualizerRouter.sol";

interface IRamsesRouter is IEqualizerRouter {
    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amountOut, bool stable);
}
