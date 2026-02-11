// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SwapParams } from "contracts/structs/LiquidityStructs.sol";

interface ISwapLib {
    function swap(
        SwapParams memory swap
    ) external payable;

    function swapMultiple(
        SwapParams[] memory swaps
    ) external;
}
