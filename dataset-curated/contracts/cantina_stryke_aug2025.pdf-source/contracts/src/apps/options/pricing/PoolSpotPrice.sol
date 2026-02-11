// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IVerifiedSpotPrice} from "../../../interfaces/IVerifiedSpotPrice.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract PoolSpotPrice is IVerifiedSpotPrice {
    function getSpotPrice(IUniswapV3Pool pool, address callAsset, uint8 callAssetDecimals)
        external
        view
        returns (uint256)
    {
        (, bytes memory result) = address(pool).staticcall(abi.encodeWithSignature("slot0()"));
        uint160 sqrtPriceX96 = abi.decode(result, (uint160));
        return _getPrice(pool, sqrtPriceX96, callAsset, callAssetDecimals);
    }

    function _getPrice(IUniswapV3Pool _pool, uint160 sqrtPriceX96, address callAsset, uint8 callAssetDecimals)
        internal
        view
        returns (uint256 price)
    {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            price = callAsset == _pool.token0()
                ? FullMath.mulDiv(priceX192, 10 ** callAssetDecimals, 1 << 192)
                : FullMath.mulDiv(1 << 192, 10 ** callAssetDecimals, priceX192);
        } else {
            uint256 priceX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);

            price = callAsset == _pool.token0()
                ? FullMath.mulDiv(priceX128, 10 ** callAssetDecimals, 1 << 128)
                : FullMath.mulDiv(1 << 128, 10 ** callAssetDecimals, priceX128);
        }
    }
}
