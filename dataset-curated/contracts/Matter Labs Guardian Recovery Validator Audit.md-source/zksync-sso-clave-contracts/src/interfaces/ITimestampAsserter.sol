// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Timestamp asserter interface
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Used to assert that the current timestamp is within a given range in AA validation context.
interface ITimestampAsserter {
  function assertTimestampInRange(uint256 start, uint256 end) external view;
}
