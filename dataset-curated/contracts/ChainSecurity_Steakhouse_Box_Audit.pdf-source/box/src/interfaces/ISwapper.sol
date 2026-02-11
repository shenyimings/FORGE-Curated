// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapper {
    /// @dev Sells `amountIn` of `input` tokens for `output` tokens.
    /// @param input The address of the input token.
    /// @param output The address of the output token.
    /// @param amountIn The amount of input tokens to sell.
    /// @param data Additional data to pass to the swapper.
    function sell(IERC20 input, IERC20 output, uint256 amountIn, bytes calldata data) external;
}
