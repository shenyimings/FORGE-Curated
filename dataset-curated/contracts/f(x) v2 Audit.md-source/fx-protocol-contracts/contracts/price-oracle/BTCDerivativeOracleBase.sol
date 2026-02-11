// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Math } from "@openzeppelin/contracts-v4/utils/math/Math.sol";

import { SpotPriceOracleBase } from "./SpotPriceOracleBase.sol";

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

abstract contract BTCDerivativeOracleBase is SpotPriceOracleBase, IPriceOracle {
  /*************
   * Constants *
   *************/

  /// @notice The Chainlink BTC/USD price feed.
  /// @dev See comments of `_readSpotPriceByChainlink` for more details.
  bytes32 public immutable Chainlink_BTC_USD_Spot;

  /*************
   * Variables *
   *************/

  /// @dev The encodings for BTCDerivative/USD spot sources.
  bytes private onchainSpotEncodings_BTCDerivativeUSD;

  /// @notice The value of maximum price deviation, multiplied by 1e18.
  uint256 public maxPriceDeviation;

  /***************
   * Constructor *
   ***************/

  constructor(bytes32 _Chainlink_BTC_USD_Spot) {
    Chainlink_BTC_USD_Spot = _Chainlink_BTC_USD_Spot;

    _updateMaxPriceDeviation(1e16); // 1%
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the BTCDerivative/USD spot prices.
  /// @return prices The list of spot price among all available sources, multiplied by 1e18.
  function getBTCDerivativeUSDSpotPrices() public view returns (uint256[] memory prices) {
    prices = _getSpotPriceByEncoding(onchainSpotEncodings_BTCDerivativeUSD);
  }

  /// @notice Return the BTCDerivative/USD anchor price, the price that is hard to manipulate in single tx.
  /// @return price The anchor price, multiplied by 1e18.
  function getBTCDerivativeUSDAnchorPrice(bool isRedeem) external view returns (uint256 price) {
    price = _getBTCDerivativeUSDAnchorPrice(isRedeem);
  }

  /// @inheritdoc IPriceOracle
  /// @dev The price is valid iff |maxPrice-minPrice|/minPrice < maxPriceDeviation
  function getPrice() external view override returns (uint256 anchorPrice, uint256 minPrice, uint256 maxPrice) {
    anchorPrice = _getBTCDerivativeUSDAnchorPrice(false);
    (minPrice, maxPrice) = _getBTCDerivativeMinMaxPrice(anchorPrice);

    uint256 cachedMaxPriceDeviation = maxPriceDeviation; // gas saving
    // use anchor price when the price deviation between anchor price and min price exceed threshold
    if ((anchorPrice - minPrice) * PRECISION > cachedMaxPriceDeviation * minPrice) {
      minPrice = anchorPrice;
    }

    // use anchor price when the price deviation between anchor price and max price exceed threshold
    if ((maxPrice - anchorPrice) * PRECISION > cachedMaxPriceDeviation * anchorPrice) {
      maxPrice = anchorPrice;
    }
  }

  /// @inheritdoc IPriceOracle
  function getExchangePrice() public view returns (uint256) {
    uint256 anchorPrice = _getBTCDerivativeUSDAnchorPrice(false);
    (uint256 minPrice, ) = _getBTCDerivativeMinMaxPrice(anchorPrice);
    // use anchor price when the price deviation between anchor price and min price exceed threshold
    if ((anchorPrice - minPrice) * PRECISION > maxPriceDeviation * minPrice) {
      minPrice = anchorPrice;
    }
    return minPrice;
  }

  /// @inheritdoc IPriceOracle
  function getLiquidatePrice() external view returns (uint256) {
    return getExchangePrice();
  }

  /// @inheritdoc IPriceOracle
  function getRedeemPrice() external view returns (uint256) {
    uint256 anchorPrice = _getBTCDerivativeUSDAnchorPrice(true);
    (, uint256 maxPrice) = _getBTCDerivativeMinMaxPrice(anchorPrice);

    // use anchor price when the price deviation between anchor price and max price exceed threshold
    if ((maxPrice - anchorPrice) * PRECISION > maxPriceDeviation * anchorPrice) {
      maxPrice = anchorPrice;
    }
    return maxPrice;
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Update the on-chain spot encodings.
  /// @param encodings The encodings to update. See `_getSpotPriceByEncoding` for more details.
  function updateOnchainSpotEncodings(bytes memory encodings) external onlyOwner {
    // validate encoding
    uint256[] memory prices = _getSpotPriceByEncoding(encodings);
    if (prices.length == 0) revert();

    onchainSpotEncodings_BTCDerivativeUSD = encodings;
  }

  /// @notice Update the value of maximum price deviation.
  /// @param newMaxPriceDeviation The new value of maximum price deviation, multiplied by 1e18.
  function updateMaxPriceDeviation(uint256 newMaxPriceDeviation) external onlyOwner {
    _updateMaxPriceDeviation(newMaxPriceDeviation);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to update the value of maximum price deviation.
  /// @param newMaxPriceDeviation The new value of maximum price deviation, multiplied by 1e18.
  function _updateMaxPriceDeviation(uint256 newMaxPriceDeviation) private {
    uint256 oldMaxPriceDeviation = maxPriceDeviation;
    if (oldMaxPriceDeviation == newMaxPriceDeviation) {
      revert ErrorParameterUnchanged();
    }

    maxPriceDeviation = newMaxPriceDeviation;

    emit UpdateMaxPriceDeviation(oldMaxPriceDeviation, newMaxPriceDeviation);
  }

  /// @dev Internal function to return the min/max BTCDerivative/USD prices.
  /// @param anchorPrice The BTCDerivative/USD anchor price, multiplied by 1e18.
  /// @return minPrice The minimum price among all available sources (including anchor price), multiplied by 1e18.
  /// @return maxPrice The maximum price among all available sources (including anchor price), multiplied by 1e18.
  function _getBTCDerivativeMinMaxPrice(
    uint256 anchorPrice
  ) internal view returns (uint256 minPrice, uint256 maxPrice) {
    minPrice = maxPrice = anchorPrice;
    uint256[] memory BTCDerivative_USD_prices = getBTCDerivativeUSDSpotPrices();

    uint256 length = BTCDerivative_USD_prices.length;
    for (uint256 i = 0; i < length; i++) {
      uint256 price = BTCDerivative_USD_prices[i];
      if (price > maxPrice) maxPrice = price;
      if (price < minPrice) minPrice = price;
    }
  }

  /// @dev Internal function to return the BTCDerivative/USD anchor price.
  /// @return price The anchor price of BTCDerivative/USD, multiplied by 1e18.
  function _getBTCDerivativeUSDAnchorPrice(bool isRedeem) internal view virtual returns (uint256 price);
}
