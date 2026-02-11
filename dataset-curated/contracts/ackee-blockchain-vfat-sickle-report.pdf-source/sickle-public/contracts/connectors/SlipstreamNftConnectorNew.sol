// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    INftLiquidityConnector,
    NftAddLiquidity,
    NftRemoveLiquidity,
    SwapParams
} from "contracts/interfaces/INftLiquidityConnector.sol";
import
    "contracts/interfaces/external/aerodrome/ISlipstreamNonfungiblePositionManager.sol";
import { UniswapV3Connector } from "contracts/connectors/UniswapV3Connector.sol";

struct SlipstreamAddLiquidityExtraData {
    int24 tickSpacing;
}

contract SlipstreamNftConnectorNew is UniswapV3Connector {
    constructor() { }

    error Unsupported();

    function swapExactTokensForTokens(SwapParams memory)
        external
        payable
        override
    {
        revert Unsupported();
    }

    function _mint(NftAddLiquidity memory addLiquidityParams)
        internal
        override
    {
        SlipstreamAddLiquidityExtraData memory extra = abi.decode(
            addLiquidityParams.extraData, (SlipstreamAddLiquidityExtraData)
        );

        ISlipstreamNonfungiblePositionManager.MintParams memory params =
        ISlipstreamNonfungiblePositionManager.MintParams({
            token0: addLiquidityParams.pool.token0,
            token1: addLiquidityParams.pool.token1,
            tickSpacing: extra.tickSpacing,
            tickLower: addLiquidityParams.tickLower,
            tickUpper: addLiquidityParams.tickUpper,
            amount0Desired: addLiquidityParams.amount0Desired,
            amount1Desired: addLiquidityParams.amount1Desired,
            amount0Min: addLiquidityParams.amount0Min,
            amount1Min: addLiquidityParams.amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 1,
            sqrtPriceX96: 0
        });

        ISlipstreamNonfungiblePositionManager(address(addLiquidityParams.nft))
            .mint(params);
    }
}
