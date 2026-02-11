// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISwapper} from "../interfaces/ISwapper.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title OneInchSwapper
/// @author 0xcarrot
/// @notice A contract that implements the ISwapper interface to facilitate token swaps using the 1inch router
contract OneInchSwapper is ISwapper {
    using SafeERC20 for IERC20;

    /// @notice The address of the 1inch router contract
    address public immutable oneInchRouter;

    /// @notice Constructs the OneInchSwapper contract
    /// @param _oneInchRouter The address of the 1inch router contract
    constructor(address _oneInchRouter) {
        oneInchRouter = _oneInchRouter;
    }

    /// @notice Executes a token swap using the 1inch router
    /// @dev This function is called by the option market contract to perform the swap
    /// @param _tokenIn The address of the input token
    /// @param _tokenOut The address of the output token (unused in this implementation)
    /// @param _amountIn The amount of input tokens to swap
    /// @param _swapData The encoded swap data for the 1inch router
    /// @return amountOut The amount of output tokens received (unused in this implementation)
    function onSwapReceived(address _tokenIn, address _tokenOut, uint256 _amountIn, bytes memory _swapData)
        external
        returns (uint256 amountOut)
    {
        IERC20(_tokenIn).safeIncreaseAllowance(oneInchRouter, _amountIn);

        // inch should directly send to the option market contract
        (bool success,) = oneInchRouter.call(_swapData);
        require(success, "1inch swap failed");
    }
}
