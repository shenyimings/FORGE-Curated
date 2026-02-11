// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IVerifiedSpotPrice {
    function getSpotPrice(IUniswapV3Pool pool, address callAsset, uint8 callAssetDecimals)
        external
        view
        returns (uint256);
}
