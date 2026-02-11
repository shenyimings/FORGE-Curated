// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC4626, IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract MockStrategy is ERC4626 {
    constructor(IERC20 asset) ERC4626(asset) ERC20("Mock Strategy", "mT") { }
}
