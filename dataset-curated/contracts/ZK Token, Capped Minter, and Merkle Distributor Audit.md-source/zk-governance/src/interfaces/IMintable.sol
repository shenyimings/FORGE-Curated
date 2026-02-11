// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMintable {
  function mint(address _to, uint256 _amount) external;
}
