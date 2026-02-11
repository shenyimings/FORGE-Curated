// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockSwap {
    mapping(address => uint256) public quotes;

    address public receiver;

    function setAmounts(address _address, uint256 amount) external {
        quotes[_address] = amount;
    }

    function setReceiver(address _receiver) external {
        receiver = _receiver;
    }

    function swap(address src, address dst, uint256 inAmount, uint256, bytes memory) external {
        IERC20(src).transferFrom(msg.sender, address(this), inAmount);

        IERC20(dst).transfer(receiver, quotes[src]);
    }

    function withdraw(address src) external {
        uint256 balance = IERC20(src).balanceOf(address(this));

        IERC20(src).transfer(receiver, balance);
    }
}
