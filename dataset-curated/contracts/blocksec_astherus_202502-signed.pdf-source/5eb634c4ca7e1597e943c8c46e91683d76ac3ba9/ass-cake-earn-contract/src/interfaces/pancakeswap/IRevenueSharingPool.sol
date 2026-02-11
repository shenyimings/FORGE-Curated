// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RevenueSharingPool Contract interface
/// @notice user who has veToken can claim revenue from this pool
interface IRevenueSharingPool {
  function claimForUser(address _user) external returns (uint256);
}
