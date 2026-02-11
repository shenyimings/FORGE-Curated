// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Math } from "@openzeppelin/contracts-v4/utils/math/Math.sol";

import { SpotPriceOracleBase } from "./SpotPriceOracleBase.sol";
import { BTCDerivativeOracleBase } from "./BTCDerivativeOracleBase.sol";

contract WBTCPriceOracle is BTCDerivativeOracleBase {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the value of maximum WBTC deviation is updated.
  /// @param oldValue The value of the previous maximum WBTC deviation.
  /// @param newValue The value of the current maximum WBTC deviation.
  event UpdateMaxWBTCDeviation(uint256 oldValue, uint256 newValue);

  /*************
   * Constants *
   *************/

  /// @notice The encoding of the Chainlink WBTC/BTC Spot.
  bytes32 public immutable Chainlink_WBTC_BTC_Spot;

  /*************
   * Variables *
   *************/

  /// @notice The value of maximum WBTC price deviation, multiplied by 1e18.
  uint256 public maxWBTCDeviation;

  /***************
   * Constructor *
   ***************/

  constructor(
    address _spotPriceOracle,
    bytes32 _Chainlink_BTC_USD_Spot,
    bytes32 _Chainlink_WBTC_BTC_Spot
  ) SpotPriceOracleBase(_spotPriceOracle) BTCDerivativeOracleBase(_Chainlink_BTC_USD_Spot) {
    Chainlink_WBTC_BTC_Spot = _Chainlink_WBTC_BTC_Spot;

    _updateMaxWBTCDeviation(2e16); // 2%
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Update the value of maximum WBTC deviation.
  /// @param newMaxWBTCDeviation The new value of maximum WBTC deviation, multiplied by 1e18.
  function updateMaxWBTCDeviation(uint256 newMaxWBTCDeviation) external onlyOwner {
    _updateMaxWBTCDeviation(newMaxWBTCDeviation);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to update the value of maximum WBTC deviation.
  /// @param newMaxWBTCDeviation The new value of maximum WBTC deviation, multiplied by 1e18.
  function _updateMaxWBTCDeviation(uint256 newMaxWBTCDeviation) private {
    uint256 oldMaxWBTCDeviation = maxWBTCDeviation;
    if (oldMaxWBTCDeviation == newMaxWBTCDeviation) {
      revert ErrorParameterUnchanged();
    }

    maxWBTCDeviation = newMaxWBTCDeviation;

    emit UpdateMaxWBTCDeviation(oldMaxWBTCDeviation, newMaxWBTCDeviation);
  }

  /// @inheritdoc BTCDerivativeOracleBase
  /// @dev [Chainlink BTC/USD spot] * [Chainlink WBTC/BTC spot]
  function _getBTCDerivativeUSDAnchorPrice(bool isRedeem) internal view virtual override returns (uint256) {
    uint256 BTC_USD_ChainlinkSpot = _readSpotPriceByChainlink(Chainlink_BTC_USD_Spot);
    uint256 WBTC_BTC_ChainlinkSpot = _readSpotPriceByChainlink(Chainlink_WBTC_BTC_Spot);
    uint256 WBTC_USD_ChainlinkSpot = (WBTC_BTC_ChainlinkSpot * BTC_USD_ChainlinkSpot) / PRECISION;
    if (!isRedeem) return WBTC_USD_ChainlinkSpot;
    else {
      uint256 cachedMaxWBTCDeviation = maxWBTCDeviation;
      if (
        PRECISION - cachedMaxWBTCDeviation <= WBTC_BTC_ChainlinkSpot &&
        WBTC_BTC_ChainlinkSpot <= PRECISION + cachedMaxWBTCDeviation
      ) {
        return WBTC_USD_ChainlinkSpot < BTC_USD_ChainlinkSpot ? BTC_USD_ChainlinkSpot : WBTC_USD_ChainlinkSpot;
      } else {
        return WBTC_USD_ChainlinkSpot;
      }
    }
  }
}
