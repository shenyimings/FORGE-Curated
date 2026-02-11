// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { AggregatorV3Interface } from "../interfaces/Chainlink/AggregatorV3Interface.sol";

contract MockAggregatorV3Interface is AggregatorV3Interface {
  uint8 public immutable decimals;

  int256 public price;

  constructor(uint8 _decimals, int256 _price) {
    decimals = _decimals;
    price = _price;
  }

  function setPrice(int256 _price) external {
    price = _price;
  }

  function description() external view override returns (string memory) {}

  function version() external view override returns (uint256) {}

  function latestAnswer() external view override returns (uint256) {
    return uint256(price);
  }

  function getRoundData(
    uint80
  )
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    roundId = 0;
    answer = price;
    startedAt = block.timestamp;
    updatedAt = block.timestamp;
    answeredInRound = 0;
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    roundId = 0;
    answer = price;
    startedAt = block.timestamp;
    updatedAt = block.timestamp;
    answeredInRound = 0;
  }
}
