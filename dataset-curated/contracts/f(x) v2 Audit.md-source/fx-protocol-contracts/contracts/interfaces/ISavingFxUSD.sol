// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISavingFxUSD {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the threshold for batch deposit is updated.
  /// @param oldThreshold The value of the previous threshold.
  /// @param newThreshold The value of the current threshold.
  event UpdateThreshold(uint256 oldThreshold, uint256 newThreshold);
  
  /// @notice Emitted when user direct request unlocking through this contract.
  /// @param owner The address of token owner.
  /// @param shares The amount of shares to unlock.
  /// @param assets The amount of corresponding assets.
  event RequestRedeem(address owner, uint256 shares, uint256 assets);
  
  /// @notice Emitted when user claim unlocked tokens.
  /// @param owner The address of token owner.
  /// @param receiver The address of token receiver.
  event Claim(address owner, address receiver);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the net asset value, multiplied by 1e18.
  function nav() external view returns (uint256);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Deposit with gauge token.
  /// @param assets The amount of gauge token.
  /// @param receiver The address of pool share recipient.
  function depositGauge(uint256 assets, address receiver) external returns (uint256);

  /// @notice Harvest the pending rewards.
  function harvest() external;

  /// @notice Request redeem.
  /// @param shares The amount of shares to request.
  /// @return assets The amount of corresponding assets.
  function requestRedeem(uint256 shares) external returns (uint256);

  /// @notice Claim unlocked tokens.
  /// @param receiver The address of recipient.
  function claim(address receiver) external;

  /// @notice Claim unlocked tokens for someone.
  /// @param owner The address of token owner.
  /// @param receiver The address of recipient.
  function claimFor(address owner, address receiver) external;
}
