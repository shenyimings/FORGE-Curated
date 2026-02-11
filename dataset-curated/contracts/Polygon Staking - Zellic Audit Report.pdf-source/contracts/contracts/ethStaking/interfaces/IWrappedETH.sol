// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWrappedETH is IERC20 {
    function wrap() external payable;

    function unwrap(uint256 _amount) external;
}
