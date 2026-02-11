// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IPool } from "./IPool.sol";

interface IAaveFundingPool is IPool {
  /**********
   * Events *
   **********/

  /// @notice Emitted when interest snapshot is taken.
  /// @param borrowIndex The borrow index, multiplied by 1e27.
  /// @param timestamp The timestamp when this snapshot is taken.
  event SnapshotAaveBorrowIndex(uint256 borrowIndex, uint256 timestamp);

  /// @notice Emitted when the open fee ratio related parameters are updated.
  /// @param ratio The open ratio value, multiplied by 1e9.
  /// @param step The open ratio step value, multiplied by 1e18.
  event UpdateOpenRatio(uint256 ratio, uint256 step);

  /// @notice Emitted when the open fee ratio is updated.
  /// @param oldRatio The value of previous close fee ratio, multiplied by 1e9.
  /// @param newRatio The value of current close fee ratio, multiplied by 1e9.
  event UpdateCloseFeeRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when the funding fee ratio is updated.
  /// @param oldRatio The value of previous funding fee ratio, multiplied by 1e9.
  /// @param newRatio The value of current funding fee ratio, multiplied by 1e9.
  event UpdateFundingRatio(uint256 oldRatio, uint256 newRatio);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the value of funding ratio, multiplied by 1e9.
  function getFundingRatio() external view returns (uint256);
}
