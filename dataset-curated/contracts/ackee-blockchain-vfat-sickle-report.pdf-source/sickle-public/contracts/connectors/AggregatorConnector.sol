// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    ILiquidityConnector,
    AddLiquidityParams,
    RemoveLiquidityParams,
    SwapParams,
    GetAmountOutParams
} from "contracts/interfaces/ILiquidityConnector.sol";

struct AggregatorExtraData {
    bytes data;
}

contract AggregatorConnector is ILiquidityConnector {
    error AggregatorSwapFailed(bytes error);
    error NotImplemented();

    address public immutable router;

    constructor(
        address router_
    ) {
        router = router_;
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

    function swapExactTokensForTokens(
        SwapParams memory swap
    ) external payable override {
        AggregatorExtraData memory extraData =
            abi.decode(swap.extraData, (AggregatorExtraData));
        (bool success, bytes memory error) = router.call(extraData.data);
        if (!success) {
            revert AggregatorSwapFailed(error);
        }
    }

    function getAmountOut(
        GetAmountOutParams memory
    ) external pure override returns (uint256) {
        revert NotImplemented();
    }
}
