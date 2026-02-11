// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPriceOracle } from "../price-oracle/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
  uint256 public anchorPrice;
  uint256 public minPrice;
  uint256 public maxPrice;

  constructor(uint256 _anchorPrice, uint256 _minPrice, uint256 _maxPrice) {
    anchorPrice = _anchorPrice;
    minPrice = _minPrice;
    maxPrice = _maxPrice;
  }

  function setPrices(uint256 _anchorPrice, uint256 _minPrice, uint256 _maxPrice) external {
    anchorPrice = _anchorPrice;
    minPrice = _minPrice;
    maxPrice = _maxPrice;
  }

  function getPrice() public view returns (uint256, uint256, uint256) {
    return (anchorPrice, minPrice, maxPrice);
  }

  /// @inheritdoc IPriceOracle
  function getExchangePrice() public view returns (uint256) {
    (, uint256 price, ) = getPrice();
    return price;
  }

  /// @inheritdoc IPriceOracle
  function getLiquidatePrice() external view returns (uint256) {
    return getExchangePrice();
  }

  /// @inheritdoc IPriceOracle
  function getRedeemPrice() external view returns (uint256) {
    (, , uint256 price) = getPrice();
    return price;
  }
}
