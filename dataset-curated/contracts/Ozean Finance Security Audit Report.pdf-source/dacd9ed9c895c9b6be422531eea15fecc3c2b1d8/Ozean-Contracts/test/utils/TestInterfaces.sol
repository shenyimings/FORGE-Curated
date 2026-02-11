// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDX is IERC20 {
    function mint(address _to, uint256 _value) external;
    function withdraw(IERC20 _coin, address _to, uint256 _amount) external;
}

interface IERC20Faucet is IERC20 {
    function mint(address account, uint256 value) external returns (bool);
}

interface IStETH is IERC20 {
    function submit(address _referral) external payable returns (uint256);
}

interface IWstETH is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external pure returns (uint256);
}
