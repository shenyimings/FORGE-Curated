// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFxUSDRegeneracy {
  /**********
   * Events *
   **********/
  
  /// @notice Emitted when rebalance/liquidate with stable token.
  /// @param amountStable The amount of stable token used.
  /// @param amountFxUSD The corresponding amount of fxUSD.
  event RebalanceWithStable(uint256 amountStable, uint256 amountFxUSD);
  
  /// @notice Emitted when buyback fxUSD with stable reserve.
  /// @param amountStable the amount of stable token used.
  /// @param amountFxUSD The amount of fxUSD bought.
  /// @param bonusFxUSD The amount of fxUSD as bonus for caller.
  event Buyback(uint256 amountStable, uint256 amountFxUSD, uint256 bonusFxUSD);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice The address of `PoolManager` contract.
  function poolManager() external view returns (address);

  /// @notice The address of stable token.
  function stableToken() external view returns (address);

  /// @notice The address of `PegKeeper` contract.
  function pegKeeper() external view returns (address);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Mint fxUSD token someone.
  function mint(address to, uint256 amount) external;

  /// @notice Burn fxUSD from someone.
  function burn(address from, uint256 amount) external;

  /// @notice Hook for rebalance/liquidate with stable token.
  /// @param amountStableToken The amount of stable token.
  /// @param amountFxUSD The amount of fxUSD.
  function onRebalanceWithStable(uint256 amountStableToken, uint256 amountFxUSD) external;

  /// @notice Buyback fxUSD with stable token.
  /// @param amountIn the amount of stable token to use.
  /// @param receiver The address of bonus receiver.
  /// @param data The hook data to PegKeeper.
  /// @return amountOut The amount of fxUSD swapped.
  /// @return bonusOut The amount of bonus fxUSD.
  function buyback(
    uint256 amountIn,
    address receiver,
    bytes calldata data
  ) external returns (uint256 amountOut, uint256 bonusOut);
}
