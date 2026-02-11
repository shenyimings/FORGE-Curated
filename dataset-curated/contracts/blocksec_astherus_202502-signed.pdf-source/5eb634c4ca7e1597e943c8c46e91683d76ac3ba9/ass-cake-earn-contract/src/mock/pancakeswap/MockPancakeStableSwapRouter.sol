// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPancakeStableSwapRouter} from "../../interfaces/pancakeswap/IPancakeStableSwapRouter.sol";

contract MockPancakeStableSwapRouter is IPancakeStableSwapRouter {
  using SafeERC20 for IERC20;
  IPancakeStableSwapRouter public swapPool;

  constructor(address _swapPool){
    swapPool = IPancakeStableSwapRouter(_swapPool);
  }

  function exactInputStableSwap(
    address[] calldata path,
    uint256[] calldata flag,
    uint256 amountIn,
    uint256 amountOutMin,
    address to
  ) external payable override returns (uint256 amountOut) {
    IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(path[0]).safeIncreaseAllowance(address(swapPool), amountIn);
    amountOut = swapPool.exactInputStableSwap(path, flag, amountIn, amountOutMin, to);
  }
}
