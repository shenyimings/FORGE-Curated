// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AddLiquidityParams,
    RemoveLiquidityParams,
    SwapParams,
    GetAmountOutParams
} from "contracts/structs/LiquidityStructs.sol";

interface ILiquidityConnector {
    function addLiquidity(
        AddLiquidityParams memory addLiquidityParams
    ) external payable;

    function removeLiquidity(
        RemoveLiquidityParams memory removeLiquidityParams
    ) external;

    function swapExactTokensForTokens(
        SwapParams memory swap
    ) external payable;

    function getAmountOut(
        GetAmountOutParams memory getAmountOutParams
    ) external view returns (uint256);
}
