// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

interface ISwapper {
    function onSwapReceived(address _tokenIn, address _tokenOut, uint256 _amountIn, bytes calldata _swapData)
        external
        returns (uint256 amountOut);
}
