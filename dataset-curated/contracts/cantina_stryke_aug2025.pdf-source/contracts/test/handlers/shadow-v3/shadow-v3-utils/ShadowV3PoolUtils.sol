// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IRamsesV3Factory} from "./IRamsesV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {ShadowV3LiquidityManagement} from "./ShadowV3LiquidityManagement.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";
import {IRamsesV3Pool} from "../../../../src/handlers/shadow-v3/IRamsesV3Pool.sol";

contract ShadowV3PoolUtils is Test {
    IRamsesV3Factory public factory;
    bytes32 public POOL_INIT_CODE_HASH;

    constructor(address _factory, bytes32 _pool_init_code_hash) {
        factory = IRamsesV3Factory(_factory);
        POOL_INIT_CODE_HASH = _pool_init_code_hash;
    }

    function deployAndInitializePool(MockERC20 tokenA, MockERC20 tokenB, int24 tickSpacing, uint160 sqrtPriceX96)
        external
        returns (address pool)
    {
        // Create a Uniswap V3 pool for the tokenA/tokenB pair with the specified fee
        pool = factory.createPool(address(tokenA), address(tokenB), tickSpacing, sqrtPriceX96);

        // Initialize the pool with the specified sqrtPriceX96
        // IUniswapV3Pool(pool).initialize(sqrtPriceX96);
    }

    struct AddLiquidityStruct {
        address liquidityManager;
        address user;
        address pool;
        int24 desiredTickLower;
        int24 desiredTickUpper;
        uint256 desiredAmount0;
        uint256 desiredAmount1;
        bool requireMint;
    }

    function addLiquidity(AddLiquidityStruct memory _params) public returns (uint256 liquidity) {
        if (_params.requireMint) {
            if (_params.desiredAmount0 > 0) {
                MockERC20(IRamsesV3Pool(_params.pool).token0()).mint(_params.user, _params.desiredAmount0);
            }
            if (_params.desiredAmount1 > 0) {
                MockERC20(IRamsesV3Pool(_params.pool).token1()).mint(_params.user, _params.desiredAmount1);
            }
        }

        vm.startPrank(_params.user);

        MockERC20(IRamsesV3Pool(_params.pool).token0()).approve(address(_params.liquidityManager), type(uint256).max);
        MockERC20(IRamsesV3Pool(_params.pool).token1()).approve(address(_params.liquidityManager), type(uint256).max);

        (liquidity,,,) = ShadowV3LiquidityManagement(_params.liquidityManager).addLiquidity(
            ShadowV3LiquidityManagement.AddLiquidityParams({
                token0: IRamsesV3Pool(_params.pool).token0(),
                token1: IRamsesV3Pool(_params.pool).token1(),
                tickSpacing: IRamsesV3Pool(_params.pool).tickSpacing(),
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
