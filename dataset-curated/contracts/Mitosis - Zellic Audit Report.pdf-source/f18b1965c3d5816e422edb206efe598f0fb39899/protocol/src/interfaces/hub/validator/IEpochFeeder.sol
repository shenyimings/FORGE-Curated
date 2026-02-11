// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IEpochFeeder
/// @notice Interface for managing epoch transitions and timing in the protocol
interface IEpochFeeder {
  /// @notice Emitted when the next interval is set
  /// @param appliedEpoch The epoch number when the interval was set
  /// @param appliedTimestamp The timestamp when the interval will be applied
  /// @param nextInterval The new interval in seconds
  event NextIntervalSet(uint256 indexed appliedEpoch, uint48 appliedTimestamp, uint48 nextInterval);

  /// @notice Returns current epoch number
  /// @return Current epoch number
  function epoch() external view returns (uint256);

  /// @notice Finds epoch number at a given timestamp using binary search
  /// @param timestamp_ Timestamp to query
  /// @return Epoch number at that timestamp
  function epochAt(uint48 timestamp_) external view returns (uint256);

  /// @notice Returns timestamp for current epoch
  /// @return Timestamp for current epoch
  function time() external view returns (uint48);

  /// @notice Returns timestamp for a given epoch
  /// @param epoch_ Epoch number to query
  /// @return Timestamp for that epoch
  function timeAt(uint256 epoch_) external view returns (uint48);

  /// @notice Returns interval between epochs
  /// @return Current interval in seconds
  function interval() external view returns (uint48);

  /// @notice Returns interval for a given epoch
  /// @param epoch_ Epoch number to query
  /// @return Interval for that epoch
  function intervalAt(uint256 epoch_) external view returns (uint48);

  /// @notice Sets the next interval
  /// @param interval_ New interval in seconds
  function setNextInterval(uint48 interval_) external;
}
