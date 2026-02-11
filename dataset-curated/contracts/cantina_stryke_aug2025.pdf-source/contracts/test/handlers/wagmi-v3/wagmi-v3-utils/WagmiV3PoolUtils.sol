// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {WagmiV3LiquidityManagement} from "./WagmiV3LiquidityManagement.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";

contract WagmiV3PoolUtils is Test {
    function deployAndInitializePool(
        IUniswapV3Factory factory,
        MockERC20 tokenA,
        MockERC20 tokenB,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool) {
        // Create a Uniswap V3 pool for the tokenA/tokenB pair with the specified fee
        pool = factory.createPool(address(tokenA), address(tokenB), fee);

        // Initialize the pool with the specified sqrtPriceX96
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
    }

    struct AddLiquidityStruct {
        address liquidityManager;
        address user;
        IUniswapV3Pool pool;
        int24 desiredTickLower;
        int24 desiredTickUpper;
        uint256 desiredAmount0;
        uint256 desiredAmount1;
        bool requireMint;
    }

    function addLiquidity(AddLiquidityStruct memory _params) public returns (uint256 liquidity) {
        if (_params.requireMint) {
            if (_params.desiredAmount0 > 0) MockERC20(_params.pool.token0()).mint(_params.user, _params.desiredAmount0);
            if (_params.desiredAmount1 > 0) MockERC20(_params.pool.token1()).mint(_params.user, _params.desiredAmount1);
        }

        vm.startPrank(_params.user);

        MockERC20(_params.pool.token0()).approve(address(_params.liquidityManager), type(uint256).max);
        MockERC20(_params.pool.token1()).approve(address(_params.liquidityManager), type(uint256).max);

        (liquidity,,,) = WagmiV3LiquidityManagement(_params.liquidityManager).addLiquidity(
            WagmiV3LiquidityManagement.AddLiquidityParams({
                token0: _params.pool.token0(),
                token1: _params.pool.token1(),
                fee: _params.pool.fee(),
                recipient: _params.user,
                tickLower: _params.desiredTickLower,
                tickUpper: _params.desiredTickUpper,
                amount0Desired: _params.desiredAmount0,
                amount1Desired: _params.desiredAmount1,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        vm.stopPrank();
    }
}
