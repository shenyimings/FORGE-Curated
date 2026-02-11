// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISwapper } from "../../src/interfaces/ISwapper.sol";

contract MockSwapper is ISwapper {
    uint256 public amountOut;

    function swap(
        address, /* assetIn */
        uint256, /* amountIn */
        address assetOut,
        uint256, /* minAmountOut */
        address recipient,
        bytes calldata /* swapperData */
    )
        external
        returns (uint256)
    {
        require(IERC20(assetOut).transfer(recipient, amountOut));
        return amountOut;
    }

    function setAmountOut(uint256 _amountOut) external {
        amountOut = _amountOut;
    }
}
