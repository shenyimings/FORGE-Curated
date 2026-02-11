// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./ISTETH.sol";

interface IWSTETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256 wstETHAmount);
    function unwrap(uint256 _wstETHAmount) external returns (uint256 stETHAmount);

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);

    function stETH() external view returns (ISTETH);
}
