// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {ISwapper} from "../interfaces/ISwapper.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ISwapRouter
/// @notice Interface for the Uniswap V3 SwapRouter
interface ISwapRouter {
    /// @notice Parameters for a single exact input swap
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
}

/// @title SwapRouterSwapper
/// @author 0xcarrot
/// @notice A contract that implements the ISwapper interface to facilitate token swaps using Uniswap V3 SwapRouter
contract SwapRouterSwapper is ISwapper {
    using SafeERC20 for IERC20;

    /// @notice The Uniswap V3 SwapRouter contract
    ISwapRouter public immutable sr;

    /// @notice Constructs the SwapRouterSwapper contract
    /// @param _sr The address of the Uniswap V3 SwapRouter contract
    constructor(address _sr) {
        sr = ISwapRouter(_sr);
    }

    /// @notice Executes a token swap using the Uniswap V3 SwapRouter
    /// @dev This function is called by the option market contract to perform the swap
    /// @param _tokenIn The address of the input token
    /// @param _tokenOut The address of the output token
    /// @param _amountIn The amount of input tokens to swap
    /// @param _swapData The encoded swap data containing fee and minimum amount out
    /// @return amountOut The amount of output tokens received
    function onSwapReceived(address _tokenIn, address _tokenOut, uint256 _amountIn, bytes memory _swapData)
        external
        returns (uint256 amountOut)
    {
        (uint24 fee, uint256 amountOutMinimum) = abi.decode(_swapData, (uint24, uint256));

        IERC20(_tokenIn).safeIncreaseAllowance(address(sr), _amountIn);

        amountOut = sr.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: fee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
