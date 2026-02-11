// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockWETH is MockERC20, Test {
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        deal(msg.sender, msg.sender.balance + amount);
    }
}
