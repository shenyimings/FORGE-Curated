// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {ISwapRouter02} from "src/interfaces/ISwapRouter02.sol";
import {BytesLib, Path} from "src/libraries/Path.sol";

contract MockRouter is Test, ISwapRouter02 {
    uint256 nextRate;

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        uint256 calcOutput = (params.amountIn * nextRate) / 10_000;
        amountOut = calcOutput >= params.amountOutMinimum ? calcOutput : params.amountOutMinimum;

        deal(params.tokenOut, address(this), amountOut);

        IERC20(params.tokenOut).transfer(params.recipient, amountOut);
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {
        (address tokenIn,,) = Path.decodeFirstPool(params.path);
        (, address tokenOut,) = Path.decodeLastPool(params.path);
        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        uint256 calcOutput = (params.amountIn * nextRate) / 10_000;
        amountOut = calcOutput >= params.amountOutMinimum ? calcOutput : params.amountOutMinimum;

        deal(tokenOut, address(this), amountOut);

        IERC20(tokenOut).transfer(params.recipient, amountOut);
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn) {
        uint256 calcInput = (params.amountOut * nextRate) / 10_000;
        amountIn = calcInput >= params.amountInMaximum ? params.amountInMaximum : calcInput;

        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);

        deal(params.tokenOut, address(this), params.amountOut);
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOut);
    }

    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn) {
        uint256 calcInput = (params.amountOut * nextRate) / 10_000;
        amountIn = calcInput >= params.amountInMaximum ? params.amountInMaximum : calcInput;

        (, address tokenIn,) = Path.decodeLastPool(params.path);
        (address tokenOut,,) = Path.decodeFirstPool(params.path);
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        deal(tokenOut, address(this), params.amountOut);
        IERC20(tokenOut).transfer(params.recipient, params.amountOut);
    }

    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] calldata path, address to)
        external
        payable
        returns (uint256 amountIn)
    {
        uint256 calcInput = (amountOut * nextRate) / 10_000;
        amountIn = calcInput >= amountInMax ? amountInMax : calcInput;

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        address tokenOut = path[path.length - 1];
        deal(tokenOut, address(this), amountOut);
        IERC20(tokenOut).transfer(to, amountOut);
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to)
        external
        payable
        returns (uint256 amountOut)
    {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        uint256 calcOutput = (amountIn * nextRate) / 10_000;
        amountOut = calcOutput >= amountOutMin ? calcOutput : amountOutMin;

        address tokenOut = path[path.length - 1];
        deal(tokenOut, address(this), amountOut);
        IERC20(tokenOut).transfer(to, amountOut);
    }

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {}

    function multicall(uint256 deadline, bytes[] calldata data) external payable returns (bytes[] memory results) {}

    function multicall(bytes32 previousBlockhash, bytes[] calldata data)
        external
        payable
        returns (bytes[] memory results)
    {}
}
