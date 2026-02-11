// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { SpotPriceOracleBase } from "./SpotPriceOracleBase.sol";

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { ITwapOracle } from "./interfaces/ITwapOracle.sol";

abstract contract LSDPriceOracleBase is SpotPriceOracleBase, IPriceOracle {
  /*************
   * Constants *
   *************/

  /// @notice The Chainlink ETH/USD price feed.
  /// @dev See comments of `_readSpotPriceByChainlink` for more details.
  bytes32 public immutable Chainlink_ETH_USD_Spot;

  /*************
   * Variables *
   *************/

  /// @dev The encodings for ETH/USD spot sources.
  bytes private onchainSpotEncodings_ETHUSD;

  /// @dev The encodings for LSD/ETH spot sources.
  bytes private onchainSpotEncodings_LSDETH;

  /// @dev The encodings for LSD/USD spot sources.
  bytes private onchainSpotEncodings_LSDUSD;

  /// @notice The value of maximum price deviation, multiplied by 1e18.
  uint256 public maxPriceDeviation;

  /***************
   * Constructor *
   ***************/

  constructor(bytes32 _Chainlink_ETH_USD_Spot) {
    Chainlink_ETH_USD_Spot = _Chainlink_ETH_USD_Spot;

    _updateMaxPriceDeviation(1e16); // 1%
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the ETH/USD spot price.
  /// @return chainlinkPrice The spot price from Chainlink price feed.
  /// @return minPrice The minimum spot price among all available sources.
  /// @return maxPrice The maximum spot price among all available sources.
  function getETHUSDSpotPrice() external view returns (uint256 chainlinkPrice, uint256 minPrice, uint256 maxPrice) {
    (chainlinkPrice, minPrice, maxPrice) = _getETHUSDSpotPrice();
  }

  /// @notice Return the ETH/USD spot prices.
  /// @return prices The list of spot price among all available sources, multiplied by 1e18.
  function getETHUSDSpotPrices() external view returns (uint256[] memory prices) {
    prices = _getSpotPriceByEncoding(onchainSpotEncodings_ETHUSD);
  }

  /// @notice Return the LSD/ETH spot prices.
  /// @return prices The list of spot price among all available sources, multiplied by 1e18.
  function getLSDETHSpotPrices() public view returns (uint256[] memory prices) {
    prices = _getSpotPriceByEncoding(onchainSpotEncodings_LSDETH);
  }

  /// @notice Return the LSD/ETH spot prices.
  /// @return prices The list of spot price among all available sources, multiplied by 1e18.
  function getLSDUSDSpotPrices() public view returns (uint256[] memory prices) {
    prices = _getSpotPriceByEncoding(onchainSpotEncodings_LSDUSD);
  }

  /// @notice Return the LSD/USD anchor price, the price that is hard to manipulate in single tx.
  /// @return price The anchor price, multiplied by 1e18.
  function getLSDUSDAnchorPrice() external view returns (uint256 price) {
    price = _getLSDUSDAnchorPrice();
  }

  /// @inheritdoc IPriceOracle
  /// @dev The price is valid iff |maxPrice-minPrice|/minPrice < maxPriceDeviation
  function getPrice() public view override returns (uint256 anchorPrice, uint256 minPrice, uint256 maxPrice) {
    anchorPrice = _getLSDUSDAnchorPrice();
    (minPrice, maxPrice) = _getLSDMinMaxPrice(anchorPrice);

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

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Update the on-chain spot encodings.
  /// @param encodings The encodings to update. See `_getSpotPriceByEncoding` for more details.
  /// @param spotType The type of the encodings.
  function updateOnchainSpotEncodings(bytes memory encodings, uint256 spotType) external onlyOwner {
    // validate encoding
    uint256[] memory prices = _getSpotPriceByEncoding(encodings);

    if (spotType == 0) {
      onchainSpotEncodings_ETHUSD = encodings;
      if (prices.length == 0) revert ErrorInvalidEncodings();
    } else if (spotType == 1) {
      onchainSpotEncodings_LSDETH = encodings;
    } else if (spotType == 2) {
      onchainSpotEncodings_LSDUSD = encodings;
    }
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

  /// @dev Internal function to calculate the ETH/USD spot price.
  /// @return chainlinkPrice The spot price from Chainlink price feed, multiplied by 1e18.
  /// @return minPrice The minimum spot price among all available sources, multiplied by 1e18.
  /// @return maxPrice The maximum spot price among all available sources, multiplied by 1e18.
  function _getETHUSDSpotPrice() internal view returns (uint256 chainlinkPrice, uint256 minPrice, uint256 maxPrice) {
    chainlinkPrice = _readSpotPriceByChainlink(Chainlink_ETH_USD_Spot);
    uint256[] memory prices = _getSpotPriceByEncoding(onchainSpotEncodings_ETHUSD);
    minPrice = maxPrice = chainlinkPrice;
    for (uint256 i = 0; i < prices.length; i++) {
      if (prices[i] > maxPrice) maxPrice = prices[i];
      if (prices[i] < minPrice) minPrice = prices[i];
    }
  }

  /// @dev Internal function to return the min/max LSD/USD prices.
  /// @param anchorPrice The LSD/USD anchor price, multiplied by 1e18.
  /// @return minPrice The minimum price among all available sources (including twap), multiplied by 1e18.
  /// @return maxPrice The maximum price among all available sources (including twap), multiplied by 1e18.
  function _getLSDMinMaxPrice(uint256 anchorPrice) internal view returns (uint256 minPrice, uint256 maxPrice) {
    minPrice = maxPrice = anchorPrice;
    (, uint256 minETHUSDPrice, uint256 maxETHUSDPrice) = _getETHUSDSpotPrice();
    uint256[] memory LSD_ETH_prices = getLSDETHSpotPrices();
    uint256[] memory LSD_USD_prices = getLSDUSDSpotPrices();

    uint256 length = LSD_ETH_prices.length;
    uint256 LSD_ETH_minPrice = type(uint256).max;
    uint256 LSD_ETH_maxPrice;
    unchecked {
      for (uint256 i = 0; i < length; i++) {
        uint256 price = LSD_ETH_prices[i];
        if (price > LSD_ETH_maxPrice) LSD_ETH_maxPrice = price;
        if (price < LSD_ETH_minPrice) LSD_ETH_minPrice = price;
      }
      if (LSD_ETH_maxPrice != 0) {
        minPrice = Math.min(minPrice, (LSD_ETH_minPrice * minETHUSDPrice) / PRECISION);
        maxPrice = Math.max(maxPrice, (LSD_ETH_maxPrice * maxETHUSDPrice) / PRECISION);
      }

      length = LSD_USD_prices.length;
      for (uint256 i = 0; i < length; i++) {
        uint256 price = LSD_USD_prices[i];
        if (price > maxPrice) maxPrice = price;
        if (price < minPrice) minPrice = price;
      }
    }
  }

  /// @dev Internal function to return the LSD/USD anchor price.
  /// @return price The anchor price of LSD/USD, multiplied by 1e18.
  function _getLSDUSDAnchorPrice() internal view virtual returns (uint256 price);
}
