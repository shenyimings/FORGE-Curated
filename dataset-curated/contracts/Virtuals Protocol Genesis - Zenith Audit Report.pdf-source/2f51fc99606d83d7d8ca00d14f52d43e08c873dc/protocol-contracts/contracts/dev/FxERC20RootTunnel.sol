// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FxERC20RootTunnel {
    using SafeERC20 for IERC20;

    function deposit(address rootToken,  uint256 amount) public {
        // transfer from depositor to this contract
        IERC20(rootToken).safeTransferFrom(
            msg.sender, // depositor
            address(this), // manager contract
            amount
        );
    }

    // exit processor
    function syncWithdraw(address rootToken, uint256 amount) public {
        // transfer from tokens to
        IERC20(rootToken).safeTransfer(msg.sender, amount);
    }
}