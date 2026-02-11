// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockRouter {
    mapping(address => uint256) quotes;
    address public receiver;

    function setQuotes(address _address, uint256 quote) external {
        quotes[_address] = quote;
    }

    function setReceiver(address _receiver) external {
        receiver = _receiver;
    }

    function swap(address src, address dst, uint256 inAmount, uint256, bytes memory) external {
        IERC20(src).transferFrom(msg.sender, address(this), inAmount);
        MockERC20(dst).mint(quotes[src]);
        IERC20(dst).transfer(receiver, quotes[src]);
    }
}
