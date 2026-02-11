// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { INuriNonfungiblePositionManager } from
    "contracts/interfaces/external/nuri/INuriNonfungiblePositionManager.sol";
import { NftAddLiquidity } from "contracts/structs/NftLiquidityStructs.sol";
import { RamsesV3Connector } from
    "contracts/connectors/ramses/RamsesV3Connector.sol";

contract NuriV3Connector is RamsesV3Connector {
    constructor() { }

    function _mint(
        NftAddLiquidity memory addLiquidityParams
    ) internal override {
        INuriNonfungiblePositionManager.MintParams memory params =
        INuriNonfungiblePositionManager.MintParams({
            token0: addLiquidityParams.pool.token0,
            token1: addLiquidityParams.pool.token1,
            fee: addLiquidityParams.pool.fee,
            tickLower: addLiquidityParams.tickLower,
            tickUpper: addLiquidityParams.tickUpper,
            amount0Desired: addLiquidityParams.amount0Desired,
            amount1Desired: addLiquidityParams.amount1Desired,
            amount0Min: addLiquidityParams.amount0Min,
            amount1Min: addLiquidityParams.amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 1
        });

        INuriNonfungiblePositionManager(address(addLiquidityParams.nft)).mint(
            params
        );
    }
}
