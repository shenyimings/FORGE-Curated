// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategy {
  function totalSupply() external view returns (uint256);

  function deposit(uint256 amount) external;

  function withdraw(uint256 amount, address recipient) external;

  function kill() external;

  function harvest(address receiver) external;
}
