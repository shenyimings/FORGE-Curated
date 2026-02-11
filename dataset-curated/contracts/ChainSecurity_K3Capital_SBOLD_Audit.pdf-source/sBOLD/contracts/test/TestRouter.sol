// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TestRouter {
    address public sBold;
    address public receiver;

    mapping(address => uint256) quotes;

    function setSBold(address _sBold) external {
        sBold = _sBold;
    }

    function setQuotes(address _address, uint256 quote) external {
        quotes[_address] = quote;
    }

    function setReceiver(address _receiver) external {
        receiver = _receiver;
    }

    function swap(address src, address dst, uint256 inAmount, uint256, bytes memory data) external {
        (bool success, ) = sBold.call(data);

        if (!success) {
            revert("fail");
        }

        IERC20(src).transferFrom(msg.sender, address(this), inAmount);
        MockERC20(dst).mint(quotes[src]);
        IERC20(dst).transfer(receiver, quotes[src]);
    }
}
