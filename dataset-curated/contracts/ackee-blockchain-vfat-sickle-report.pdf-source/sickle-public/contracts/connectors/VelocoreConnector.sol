// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    ILiquidityConnector,
    AddLiquidityParams,
    RemoveLiquidityParams,
    SwapParams,
    GetAmountOutParams
} from "contracts/interfaces/ILiquidityConnector.sol";
import { IUniswapV2Router02 } from
    "contracts/interfaces/external/uniswap/IUniswapV2Router02.sol";
import { IWETH9 } from "contracts/interfaces/external/IWETH.sol";

struct VelocoreExtraData {
    address[] path;
}

contract VelocoreConnector is ILiquidityConnector {
    error NotImplemented();

    address public immutable wethContractAddress;

    constructor(
        address wethContractAddress_
    ) {
        wethContractAddress = wethContractAddress_;
    }

    function swapExactTokensForTokens(
        SwapParams memory swap
    ) external payable override {
        VelocoreExtraData memory extraData =
            abi.decode(swap.extraData, (VelocoreExtraData));

        uint256 length = extraData.path.length;
        for (uint256 i; i < length;) {
            if (extraData.path[i] == wethContractAddress) {
                extraData.path[i] = address(0); // Velocore implem detail
            }
            unchecked {
                i++;
            }
        }

        uint256[] memory amountsOut;

        if (extraData.path[0] == address(0)) {
            IWETH9(wethContractAddress).withdraw(swap.amountIn);
            amountsOut = IUniswapV2Router02(swap.router).swapExactETHForTokens{
                value: swap.amountIn
            }(
                swap.minAmountOut,
                extraData.path,
                address(this),
                block.timestamp + 1
            );
        } else {
            amountsOut = IUniswapV2Router02(swap.router)
                .swapExactTokensForTokens(
                swap.amountIn,
                swap.minAmountOut,
                extraData.path,
                address(this),
                block.timestamp + 1
            );
        }

        if (extraData.path[extraData.path.length - 1] == address(0)) {
            IWETH9(wethContractAddress).deposit{
                value: amountsOut[amountsOut.length - 1]
            }();
        }
    }

    function addLiquidity(
        AddLiquidityParams memory
    ) external payable override {
        revert NotImplemented();
    }

    function removeLiquidity(
        RemoveLiquidityParams memory
    ) external pure override {
        revert NotImplemented();
    }

    function getAmountOut(
        GetAmountOutParams memory
    ) external pure override returns (uint256) {
        revert NotImplemented();
    }
}
