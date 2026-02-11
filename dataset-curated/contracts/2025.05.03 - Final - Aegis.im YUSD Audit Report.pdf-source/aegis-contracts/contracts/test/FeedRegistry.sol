// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract FeedRegistry {
  uint256 updatedAt;

  mapping(address => mapping(address => int256)) private _prices;

  function decimals(address, address) external pure returns (uint8) {
    return 8;
  }

  function latestRoundData(address base, address quote) external view returns (uint80, int256, uint256, uint256, uint80) {
    return (1, _prices[base][quote], block.timestamp, updatedAt == 0 ? block.timestamp : updatedAt, 1);
  }

  function setPrice(address base, address quote, int256 price) external {
    _prices[base][quote] = price;
  }

  function setUpdatedAt(uint256 val) external {
    updatedAt = val;
  }
}
