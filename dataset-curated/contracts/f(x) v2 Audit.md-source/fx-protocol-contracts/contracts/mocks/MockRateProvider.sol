// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IRateProvider } from "../rate-provider/interfaces/IRateProvider.sol";

contract MockRateProvider is IRateProvider {
  uint256 public rate;

  constructor(uint256 _rate) {
    rate = _rate;
  }

  function setRate(uint256 _rate) external {
    rate = _rate;
  }

  function getRate() external view returns (uint256) {
    return rate;
  }
}
