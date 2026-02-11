// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPriceOracle {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the value of maximum price deviation is updated.
  /// @param oldValue The value of the previous maximum price deviation.
  /// @param newValue The value of the current maximum price deviation.
  event UpdateMaxPriceDeviation(uint256 oldValue, uint256 newValue);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the oracle price with 18 decimal places.
  /// @return anchorPrice The anchor price for this asset, multiplied by 1e18. It should be hard to manipulate,
  ///         like time-weighted average price or chainlink spot price.
  /// @return minPrice The minimum oracle price among all available price sources (including twap), multiplied by 1e18.
  /// @return maxPrice The maximum oracle price among all available price sources (including twap), multiplied by 1e18.
  function getPrice() external view returns (uint256 anchorPrice, uint256 minPrice, uint256 maxPrice);

  /// @notice Return the oracle price for exchange with 18 decimal places.
  function getExchangePrice() external view returns (uint256);

  /// @notice Return the oracle price for liquidation with 18 decimal places.
  function getLiquidatePrice() external view returns (uint256);

  /// @notice Return the oracle price for redemption with 18 decimal places.
  function getRedeemPrice() external view returns (uint256);
}
