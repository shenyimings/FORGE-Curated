// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/// @title OracleRelay Interface
interface IOracleRelay {
  function underlying() external view returns (address);
  function currentValue() external view returns (uint256 price);
}
