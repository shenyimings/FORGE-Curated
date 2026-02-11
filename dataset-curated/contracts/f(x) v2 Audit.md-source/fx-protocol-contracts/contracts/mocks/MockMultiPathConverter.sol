// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IWrappedEther } from "../interfaces/IWrappedEther.sol";

contract MockMultiPathConverter {
  using SafeERC20 for IERC20;

  /*************
   * Constants *
   *************/

  /// @dev The address of WETH token.
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  address tokenOut;
  uint256 amountOut;

  function setTokenOut(address _tokenOut, uint256 _amountOut) external {
    tokenOut = _tokenOut;
    amountOut = _amountOut;
  }

  function convert(address _tokenIn, uint256 _amount, uint256, uint256[] calldata) external payable returns (uint256) {
    if (_tokenIn == address(0)) {
      IWrappedEther(WETH).deposit{ value: _amount }();
      IERC20(WETH).safeTransfer(address(this), _amount);
    } else {
      // convert all approved.
      if (_amount == type(uint256).max) {
        _amount = IERC20(_tokenIn).allowance(msg.sender, address(this));
      }
      IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);
    }
    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    return amountOut;
  }
}
