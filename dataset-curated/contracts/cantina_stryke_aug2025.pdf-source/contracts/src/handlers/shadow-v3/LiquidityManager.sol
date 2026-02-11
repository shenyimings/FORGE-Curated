// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Interfaces
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Libraries
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {IRamsesV3Pool} from "./IRamsesV3Pool.sol";

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Uniswap V3
abstract contract LiquidityManager is IUniswapV3MintCallback {
    address public immutable factory;
    bytes32 public immutable POOL_INIT_CODE_HASH;

    struct PoolKey {
        address token0;
        address token1;
        int24 tickSpacing;
    }

    constructor(address _factory, bytes32 _pool_init_code_hash) {
        factory = _factory;
        POOL_INIT_CODE_HASH = _pool_init_code_hash;
    }

    struct MintCallbackData {
        PoolKey poolKey;
        address payer;
    }

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        verifyCallback(factory, decoded.poolKey);

        if (amount0Owed > 0) {
            pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
        }
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        int24 tickSpacing;
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Add liquidity to an initialized pool
    function addLiquidity(AddLiquidityParams memory params)
        public
        returns (uint128 liquidity, uint256 amount0, uint256 amount1, IUniswapV3Pool pool)
    {
        PoolKey memory poolKey =
            PoolKey({token0: params.token0, token1: params.token1, tickSpacing: params.tickSpacing});

        pool = IUniswapV3Pool(computeAddress(factory, poolKey));

        // compute the liquidity amount
        {
            (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, params.amount0Desired, params.amount1Desired
            );
        }

        (amount0, amount1) = IRamsesV3Pool(address(pool)).mint(
            params.recipient,
            uint256(0),
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(address token, address payer, address recipient, uint256 value) internal {
        // pull payment
        if (payer == address(this)) {
            SafeERC20.safeTransfer(IERC20(token), recipient, value);
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), payer, recipient, value);
        }
    }

    function getPoolKey(address tokenA, address tokenB, int24 tickSpacing) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, tickSpacing: tickSpacing});
    }

    function computeAddress(address _factory, PoolKey memory key) internal view returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encode(key.token0, key.token1, key.tickSpacing)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    function verifyCallback(address _factory, address tokenA, address tokenB, int24 tickSpacing)
        internal
        view
        returns (IUniswapV3Pool pool)
    {
        return verifyCallback(_factory, getPoolKey(tokenA, tokenB, tickSpacing));
    }

    function verifyCallback(address _factory, PoolKey memory poolKey) internal view returns (IUniswapV3Pool pool) {
        pool = IUniswapV3Pool(computeAddress(_factory, poolKey));
        require(msg.sender == address(pool));
    }
}
