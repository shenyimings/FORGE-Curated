// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import
    "contracts/interfaces/external/aerodrome/ISlipstreamNonfungiblePositionManager.sol";

import {
    ILiquidityConnector,
    AddLiquidityParams,
    RemoveLiquidityParams,
    SwapParams,
    GetAmountOutParams
} from "contracts/interfaces/ILiquidityConnector.sol";

struct SlipstreamAddLiquidityExtraData {
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;
    int24 tickSpacing;
}

struct SlipstreamRemoveLiquidityExtraData {
    uint256 tokenId;
    uint128 liquidity;
    uint128 amount0Max;
    uint128 amount1Max;
}

contract SlipstreamNftConnector is ILiquidityConnector {
    constructor() { }

    error Unsupported();

    function addLiquidity(
        AddLiquidityParams memory addLiquidityParams
    ) external payable override {
        SlipstreamAddLiquidityExtraData memory extra = abi.decode(
            addLiquidityParams.extraData, (SlipstreamAddLiquidityExtraData)
        );

        if (extra.tokenId == 0) {
            ISlipstreamNonfungiblePositionManager.MintParams memory params =
            ISlipstreamNonfungiblePositionManager.MintParams({
                token0: addLiquidityParams.tokens[0],
                token1: addLiquidityParams.tokens[1],
                tickSpacing: extra.tickSpacing,
                tickLower: extra.tickLower,
                tickUpper: extra.tickUpper,
                amount0Desired: addLiquidityParams.desiredAmounts[0],
                amount1Desired: addLiquidityParams.desiredAmounts[1],
                amount0Min: addLiquidityParams.minAmounts[0],
                amount1Min: addLiquidityParams.minAmounts[1],
                recipient: address(this),
                deadline: block.timestamp + 1,
                sqrtPriceX96: 0
            });

            ISlipstreamNonfungiblePositionManager(addLiquidityParams.router)
                .mint(params);
        } else {
            ISlipstreamNonfungiblePositionManager.IncreaseLiquidityParams memory
                params = ISlipstreamNonfungiblePositionManager
                    .IncreaseLiquidityParams({
                    tokenId: extra.tokenId,
                    amount0Desired: addLiquidityParams.desiredAmounts[0],
                    amount1Desired: addLiquidityParams.desiredAmounts[1],
                    amount0Min: addLiquidityParams.minAmounts[0],
                    amount1Min: addLiquidityParams.minAmounts[1],
                    deadline: block.timestamp + 1
                });

            ISlipstreamNonfungiblePositionManager(addLiquidityParams.router)
                .increaseLiquidity(params);
        }
    }

    function removeLiquidity(
        RemoveLiquidityParams memory removeLiquidityParams
    ) external override {
        SlipstreamRemoveLiquidityExtraData memory extra = abi.decode(
            removeLiquidityParams.extraData,
            (SlipstreamRemoveLiquidityExtraData)
        );

        ISlipstreamNonfungiblePositionManager.DecreaseLiquidityParams memory
            params = ISlipstreamNonfungiblePositionManager
                .DecreaseLiquidityParams({
                tokenId: extra.tokenId,
                liquidity: extra.liquidity,
                amount0Min: removeLiquidityParams.minAmountsOut[0],
                amount1Min: removeLiquidityParams.minAmountsOut[1],
                deadline: block.timestamp + 1
            });

        ISlipstreamNonfungiblePositionManager(removeLiquidityParams.router)
            .decreaseLiquidity(params);

        ISlipstreamNonfungiblePositionManager(removeLiquidityParams.router)
            .collect(
            ISlipstreamNonfungiblePositionManager.CollectParams({
                tokenId: extra.tokenId,
                recipient: address(this),
                amount0Max: extra.amount0Max,
                amount1Max: extra.amount1Max
            })
        );

        (,,,,,,, uint128 liquidity,,,,) = ISlipstreamNonfungiblePositionManager(
            removeLiquidityParams.router
        ).positions(extra.tokenId);
        if (liquidity == 0) {
            ISlipstreamNonfungiblePositionManager(removeLiquidityParams.router)
                .burn(extra.tokenId);
        }
    }

    function swapExactTokensForTokens(
        SwapParams memory
    ) external payable override {
        revert Unsupported();
    }

    function getAmountOut(
        GetAmountOutParams memory
    ) external pure override returns (uint256) {
        revert Unsupported();
    }
}
