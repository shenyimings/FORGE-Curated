// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RevenueSharingPoolGateway Contract interface
/// @notice user who has veToken can claim revenue from the pool gateway

interface IRevenueSharingPoolGateway {
  function claimMultipleWithoutProxy(address[] calldata _revenueSharingPools, address _for) external;
}
