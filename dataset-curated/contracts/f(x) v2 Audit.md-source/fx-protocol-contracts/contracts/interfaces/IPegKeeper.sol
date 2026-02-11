// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPegKeeper {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the converter contract is updated.
  /// @param oldConverter The address of previous converter contract.
  /// @param newConverter The address of current converter contract.
  event UpdateConverter(address indexed oldConverter, address indexed newConverter);

  /// @notice Emitted when the curve pool contract is updated.
  /// @param oldPool The address of previous curve pool contract.
  /// @param newPool The address of current curve pool contract.
  event UpdateCurvePool(address indexed oldPool, address indexed newPool);

  /// @notice Emitted when the price threshold is updated.
  /// @param oldThreshold The value of previous price threshold
  /// @param newThreshold The value of current price threshold
  event UpdatePriceThreshold(uint256 oldThreshold, uint256 newThreshold);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return whether borrow for fxUSD is allowed.
  function isBorrowAllowed() external view returns (bool);

  /// @notice Return whether funding costs is enabled.
  function isFundingEnabled() external view returns (bool);
  
  /// @notice Return the price of fxUSD, multiplied by 1e18
  function getFxUSDPrice() external view returns (uint256);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Buyback fxUSD with stable reserve in FxUSDSave.
  /// @param amountIn the amount of stable token to use.
  /// @param data The hook data to `onSwap`.
  /// @return amountOut The amount of fxUSD swapped.
  /// @return bonusOut The amount of bonus fxUSD.
  function buyback(uint256 amountIn, bytes calldata data) external returns (uint256 amountOut, uint256 bonusOut);

  /// @notice Stabilize the fxUSD price in curve pool.
  /// @param srcToken The address of source token (fxUSD or stable token).
  /// @param amountIn the amount of source token to use.
  /// @param data The hook data to `onSwap`.
  /// @return amountOut The amount of target token swapped.
  /// @return bonusOut The amount of bonus token.
  function stabilize(
    address srcToken,
    uint256 amountIn,
    bytes calldata data
  ) external returns (uint256 amountOut, uint256 bonusOut);

  /// @notice Swap callback from `buyback` and `stabilize`.
  /// @param srcToken The address of source token.
  /// @param srcToken The address of target token.
  /// @param amountIn the amount of source token to use.
  /// @param data The callback data.
  /// @return amountOut The amount of target token swapped.
  function onSwap(
    address srcToken,
    address targetToken,
    uint256 amountIn,
    bytes calldata data
  ) external returns (uint256 amountOut);
}
