// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title SlisBNBProvider Contract interface
/// @notice Convert slisBNB to ClisBNB
///         and allows holder to delegate clisBNB to Lista's MPC wallet
///         ,then participate LaunchPools
interface ISlisBNBProvider {
  function provide(uint256 _amount, address _delegateTo) external returns (uint256);
  function delegateAllTo(address _newDelegateTo) external;
  function release(address _recipient, uint256 _amount) external returns (uint256);
}
