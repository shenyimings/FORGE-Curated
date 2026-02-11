// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {V3BaseHandlerVe33Shadow} from "../V3BaseHandlerVe33Shadow.sol";
import {LiquidityManager} from "./LiquidityManager.sol";

import {IV3Pool} from "../../interfaces/handlers/V3/IV3Pool.sol";
import {IRamsesV3Pool} from "./IRamsesV3Pool.sol";

interface IGaugeV3 {
    function getPeriodReward(
        uint256 period,
        address[] calldata tokens,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        address receiver
    ) external;
}

/// @title ShadowV3Handler
/// @author 0xcarrot
/// @notice Handles Shadow V3 specific operations
/// @dev Inherits from V3BaseHandlerVe33Shadow and LiquidityManager
contract ShadowV3Handler is V3BaseHandlerVe33Shadow, LiquidityManager {
    /// @notice Constructs the ShadowV3Handler contract
    /// @param _feeReceiver Address to receive fees
    /// @param _factory Address of the Shadow V3 factory
    /// @param _pool_init_code_hash Initialization code hash for Shadow V3 pools
    constructor(address _feeReceiver, address _factory, bytes32 _pool_init_code_hash)
        V3BaseHandlerVe33Shadow(_feeReceiver)
        LiquidityManager(_factory, _pool_init_code_hash)
    {}

    /// @notice Adds liquidity to a Shadow V3 pool
    /// @dev Overrides the _addLiquidity function from V3BaseHandlerVe33
    /// @param self Whether the function is called internally or externally
    /// @param tki TokenIdInfo struct containing token and fee information
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0 The amount of token0 to add as liquidity
    /// @param amount1 The amount of token1 to add as liquidity
    /// @return l The amount of liquidity added
    /// @return a0 The actual amount of token0 added as liquidity
    /// @return a1 The actual amount of token1 added as liquidity
    function _addLiquidity(
        bool self,
        TokenIdInfo memory tki,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal virtual override returns (uint128 l, uint256 a0, uint256 a1) {
        if (!self) {
            (l, a0, a1,) = addLiquidity(
                LiquidityManager.AddLiquidityParams({
                    token0: tki.token0,
                    token1: tki.token1,
                    tickSpacing: tki.tickSpacing,
                    recipient: address(this),
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: amount0,
                    amount1Min: amount1
                })
            );
        } else {
            (l, a0, a1,) = ShadowV3Handler(address(this)).addLiquidity(
                LiquidityManager.AddLiquidityParams({
                    token0: tki.token0,
                    token1: tki.token1,
                    tickSpacing: tki.tickSpacing,
                    recipient: address(this),
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: amount0,
                    amount1Min: amount1
                })
            );
        }
    }

    /// @notice Removes liquidity from a Shadow V3 pool
    /// @dev Overrides the _removeLiquidity function from V3BaseHandler
    /// @param _pool The Shadow V3 pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidity The amount of liquidity to remove
    /// @return amount0 The amount of token0 removed
    /// @return amount1 The amount of token1 removed
    function _removeLiquidity(IV3Pool _pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        virtual
        override
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = IRamsesV3Pool(address(_pool)).burn(uint256(0), tickLower, tickUpper, liquidity);
    }

    function getGaugeRewards(
        address _gauge,
        uint256 period,
        address[] calldata tokens,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        address receiver
    ) external onlyOwner {
        IGaugeV3(_gauge).getPeriodReward(period, tokens, owner, index, tickLower, tickUpper, receiver);
    }
}
