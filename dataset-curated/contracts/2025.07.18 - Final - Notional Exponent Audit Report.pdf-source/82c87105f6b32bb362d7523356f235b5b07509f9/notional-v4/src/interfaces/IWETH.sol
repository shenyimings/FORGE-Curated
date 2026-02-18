// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface WETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

