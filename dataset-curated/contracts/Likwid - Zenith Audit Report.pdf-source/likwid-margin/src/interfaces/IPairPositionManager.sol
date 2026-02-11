// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PoolKey} from "../types/PoolKey.sol";
import {PoolId} from "../types/PoolId.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PairPosition} from "../libraries/PairPosition.sol";

interface IPairPositionManager is IERC721 {
    event ModifyLiquidity(
        PoolId indexed poolId,
        uint256 indexed tokenId,
        address indexed sender,
        int128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Return the position with the given ID
    /// @param positionId The ID of the position to retrieve
    /// @return _position The position with the given ID
    function getPositionState(uint256 positionId) external view returns (PairPosition.State memory);

    /// @notice Creates a new liquidity position and adds liquidity to it.
    /// @param key The pool key of the position to create.
    /// @param amount0 The amount of token0 to add.
    /// @param amount1 The amount of token1 to add.
    /// @param amount0Min The minimum amount of token0 to deposit.
    /// @param amount1Min The minimum amount of token1 to deposit.
    /// @return tokenId The ID of the newly created position.
    /// @return liquidity The amount of liquidity minted for the position.
    function addLiquidity(PoolKey memory key, uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity);

    /// @notice Creates a new liquidity position and adds liquidity to it.
    /// @param tokenId The ID of the position to add liquidity to.
    /// @param amount0 The amount of token0 to add.
    /// @param amount1 The amount of token1 to add.
    /// @param amount0Min The minimum amount of token0 to deposit.
    /// @param amount1Min The minimum amount of token1 to deposit.
    /// @return liquidity The amount of liquidity minted for the position.
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable returns (uint128 liquidity);

    /// @notice Removes liquidity from an existing position.
    /// @param tokenId The ID of the position to remove liquidity from.
    /// @param liquidity The amount of liquidity to remove.
    /// @param amount0Min The minimum amount of token0 to receive.
    /// @param amount1Min The minimum amount of token1 to receive.
    /// @return amount0 The amount of token0 received.
    /// @return amount1 The amount of token1 received.
    function removeLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min)
        external
        returns (uint256 amount0, uint256 amount1);

    struct SwapInputParams {
        PoolId poolId;
        bool zeroForOne;
        address to;
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 deadline;
    }

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible.
    /// @param params The parameters for the swap.
    /// @return swapFee The fee paid for the swap.
    /// @return feeAmount The amount of the fee.
    /// @return amountOut The amount of output tokens received.
    function exactInput(SwapInputParams calldata params)
        external
        payable
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountOut);

    struct SwapOutputParams {
        PoolId poolId;
        bool zeroForOne;
        address to;
        uint256 amountInMax;
        uint256 amountOut;
        uint256 deadline;
    }

    /// @notice Swaps as few input tokens as possible for an exact amount of output tokens.
    /// @param params The parameters for the swap.
    /// @return swapFee The fee paid for the swap.
    /// @return feeAmount The amount of the fee.
    /// @return amountIn The amount of input tokens paid.
    function exactOutput(SwapOutputParams calldata params)
        external
        payable
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountIn);
}
