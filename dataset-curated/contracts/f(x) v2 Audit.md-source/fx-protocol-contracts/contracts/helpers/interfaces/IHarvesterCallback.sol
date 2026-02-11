// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IHarvesterCallback {
  /// @notice Hook function to handle harvested rewards.
  /// @param token The address of token.
  /// @param amount The amount of tokens.
  function onHarvest(address token, uint256 amount) external;
}
