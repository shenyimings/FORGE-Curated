// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAegisOracle {
  function decimals() external pure returns (uint8);

  function yusdUSDPrice() external view returns (int256);

  function lastUpdateTimestamp() external view returns (uint32);
}
