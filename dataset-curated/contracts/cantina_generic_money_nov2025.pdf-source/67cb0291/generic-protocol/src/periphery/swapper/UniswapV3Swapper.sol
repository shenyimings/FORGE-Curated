// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapper } from "../../interfaces/ISwapper.sol";
import { IUniswapSwapRouterLike } from "../../interfaces/IUniswapSwapRouterLike.sol";
import { IUniswapQuoterLike } from "../../interfaces/IUniswapQuoterLike.sol";

/**
 * @title UniswapV3Swapper
 * @notice A token swapper implementation using Uniswap V3
 * @dev This contract implements the ISwapper interface to provide token swapping
 * functionality through Uniswap V3 pools. It supports single-hop swaps with
 * configurable fee tiers and slippage protection.
 */
contract UniswapV3Swapper is ISwapper {
    using SafeERC20 for IERC20;

    /**
     * @notice The Uniswap V3 router contract used for executing swaps
     */
    IUniswapSwapRouterLike public immutable uniswapRouter;
    /**
     * @notice The Uniswap V3 quoter contract used for price quotes
     */
    IUniswapQuoterLike public immutable quoter;

    /**
     * @notice Parameters required for Uniswap V3 swaps
     * @param fee The fee tier of the Uniswap V3 pool to be used for the swap
     */
    struct SwapperParams {
        uint24 fee; // The fee tier of the Uniswap V3 pool to be used for the swap
    }

    /**
     * @notice Thrown when a zero address is provided where a valid address is required
     */
    error ZeroAddress();
    /**
     * @notice Thrown when identical addresses are provided for input and output tokens
     */
    error IdenticalAddresses();
    /**
     * @notice Thrown when the input amount is zero or invalid
     */
    error InsufficientInputAmount();
    /**
     * @notice Thrown when the output amount is below the minimum required
     */
    error InsufficientOutputAmount();

    /**
     * @notice Constructs the UniswapV3Swapper contract
     * @param uniswapRouter_ The address of the Uniswap V3 router contract
     * @param quoter_ The address of the Uniswap V3 quoter contract
     */
    constructor(IUniswapSwapRouterLike uniswapRouter_, IUniswapQuoterLike quoter_) {
        uniswapRouter = uniswapRouter_;
        quoter = quoter_;
    }

    /**
     * @notice Swaps tokens using Uniswap V3
     * @dev Executes a single-hop token swap through Uniswap V3 with the specified parameters.
     * The function validates inputs, approves tokens, and executes the swap through the router.
     * @param assetIn The address of the input token to swap from
     * @param amountIn The amount of input tokens to swap
     * @param assetOut The address of the output token to swap to
     * @param minAmountOut The minimum amount of output tokens expected (slippage protection)
     * @param recipient The address that will receive the output tokens
     * @param swapperParams ABI-encoded SwapperParams struct containing the fee tier
     * @return amountOut The actual amount of output tokens received from the swap
     */
    function swap(
        address assetIn,
        uint256 amountIn,
        address assetOut,
        uint256 minAmountOut,
        address recipient,
        bytes calldata swapperParams
    )
        public
        virtual
        returns (uint256 amountOut)
    {
        require(assetIn != address(0), ZeroAddress());
        require(assetOut != address(0), ZeroAddress());
        require(assetIn != assetOut, IdenticalAddresses());
        require(amountIn > 0, InsufficientInputAmount());
        require(minAmountOut > 0, InsufficientOutputAmount());

        SwapperParams memory params = abi.decode(swapperParams, (SwapperParams));
        IERC20(assetIn).forceApprove(address(uniswapRouter), amountIn);
        amountOut = uniswapRouter.exactInputSingle(
            IUniswapSwapRouterLike.ExactInputSingleParams({
                tokenIn: assetIn,
                tokenOut: assetOut,
                fee: params.fee,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        require(amountOut >= minAmountOut, InsufficientOutputAmount());
        emit Swap(assetIn, assetOut, amountIn, amountOut);
    }

    /**
     * @notice Quotes the amount of output tokens for a given input
     * @dev Uses the Uniswap V3 quoter to estimate the output amount without executing the swap.
     * This is useful for price discovery and slippage calculations.
     * @param assetIn The address of the input token
     * @param amountIn The amount of input tokens
     * @param assetOut The address of the output token
     * @param swapperParams ABI-encoded SwapperParams struct containing the fee tier
     * @return amountOut The estimated amount of output tokens
     */
    function getAmountOut(
        address assetIn,
        uint256 amountIn,
        address assetOut,
        bytes calldata swapperParams
    )
        public
        virtual
        returns (uint256 amountOut)
    {
        SwapperParams memory params = abi.decode(swapperParams, (SwapperParams));
        return quoter.quoteExactInputSingle(assetIn, assetOut, params.fee, amountIn, 0);
    }
}
