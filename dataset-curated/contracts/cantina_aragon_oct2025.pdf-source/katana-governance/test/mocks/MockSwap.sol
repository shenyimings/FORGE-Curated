// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";

contract MockSwap {
    event Swapped(address from, address to, uint256 amount);

    // Swaps tokenA into tokenB and automatically transfers new tokenB amounts to `recipient`.
    function swapToRecipient(address tokenA, address tokenB, uint256 amount, address recipient) public {
        bool successA = IERC20(tokenA).transferFrom(msg.sender, address(this), amount);
        require(successA, "Transfer failed");

        MockERC20(tokenB).mint(address(this), amount * 2);
        bool successB = IERC20(tokenB).transfer(recipient, amount * 2);
        require(successB, "Transfer failed");
    }

    function swap(address tokenA, address tokenB, uint256 amount) public {
        swapToRecipient(tokenA, tokenB, amount, msg.sender);
    }
}
