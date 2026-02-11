// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFxUSDBasePool {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the stable depeg price is updated.
  /// @param oldPrice The value of previous depeg price, multiplied by 1e18.
  /// @param newPrice The value of current depeg price, multiplied by 1e18.
  event UpdateStableDepegPrice(uint256 oldPrice, uint256 newPrice);

  /// @notice Emitted when the redeem cool down period is updated.
  /// @param oldPeriod The value of previous redeem cool down period.
  /// @param newPeriod The value of current redeem cool down period.
  event UpdateRedeemCoolDownPeriod(uint256 oldPeriod, uint256 newPeriod);

  /// @notice Emitted when the instant redeem fee ratio is updated.
  /// @param oldRatio The value of previous instant redeem fee ratio, multiplied by 1e18.
  /// @param newRatio The value of current instant redeem fee ratio, multiplied by 1e18.
  event UpdateInstantRedeemFeeRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when deposit tokens.
  /// @param caller The address of caller.
  /// @param receiver The address of pool share recipient.
  /// @param tokenIn The address of input token.
  /// @param amountDeposited The amount of input tokens.
  /// @param amountSharesOut The amount of pool shares minted.
  event Deposit(
    address indexed caller,
    address indexed receiver,
    address indexed tokenIn,
    uint256 amountDeposited,
    uint256 amountSharesOut
  );
  
  /// @notice Emitted when users request redeem.
  /// @param caller The address of caller.
  /// @param shares The amount of shares to redeem.
  /// @param unlockAt The timestamp when this share can be redeemed.
  event RequestRedeem(address indexed caller, uint256 shares, uint256 unlockAt);

  /// @notice Emitted when redeem pool shares.
  /// @param caller The address of caller.
  /// @param receiver The address of pool share recipient.
  /// @param amountSharesToRedeem The amount of pool shares burned.
  /// @param amountYieldTokenOut The amount of yield tokens redeemed.
  /// @param amountStableTokenOut The amount of stable tokens redeemed.
  event Redeem(
    address indexed caller,
    address indexed receiver,
    uint256 amountSharesToRedeem,
    uint256 amountYieldTokenOut,
    uint256 amountStableTokenOut
  );

  /// @notice Emitted when instant redeem pool shares.
  /// @param caller The address of caller.
  /// @param receiver The address of pool share recipient.
  /// @param amountSharesToRedeem The amount of pool shares burned.
  /// @param amountYieldTokenOut The amount of yield tokens redeemed.
  /// @param amountStableTokenOut The amount of stable tokens redeemed.
  event InstantRedeem(
    address indexed caller,
    address indexed receiver,
    uint256 amountSharesToRedeem,
    uint256 amountYieldTokenOut,
    uint256 amountStableTokenOut
  );

  /// @notice Emitted when rebalance or liquidate.
  /// @param caller The address of caller.
  /// @param tokenIn The address of input token.
  /// @param amountTokenIn The amount of input token used.
  /// @param amountCollateral The amount of collateral token rebalanced.
  /// @param amountYieldToken The amount of yield token used.
  /// @param amountStableToken The amount of stable token used.
  event Rebalance(
    address indexed caller,
    address indexed tokenIn,
    uint256 amountTokenIn,
    uint256 amountCollateral,
    uint256 amountYieldToken,
    uint256 amountStableToken
  );

  /// @notice Emitted when arbitrage in curve pool.
  /// @param caller The address of caller.
  /// @param tokenIn The address of input token.
  /// @param amountIn The amount of input token used.
  /// @param amountOut The amount of output token swapped.
  /// @param bonusOut The amount of bonus token.
  event Arbitrage(
    address indexed caller,
    address indexed tokenIn,
    uint256 amountIn,
    uint256 amountOut,
    uint256 bonusOut
  );

  /*************************
   * Public View Functions *
   *************************/

  /// @notice The address of yield token.
  function yieldToken() external view returns (address);

  /// @notice The address of stable token.
  function stableToken() external view returns (address);

  /// @notice The total amount of yield token managed in this contract
  function totalYieldToken() external view returns (uint256);

  /// @notice The total amount of stable token managed in this contract
  function totalStableToken() external view returns (uint256);

  /// @notice The net asset value, multiplied by 1e18.
  function nav() external view returns (uint256);

  /// @notice Return the stable token price, multiplied by 1e18.
  function getStableTokenPrice() external view returns (uint256);

  /// @notice Return the stable token price with scaling to 18 decimals, multiplied by 1e18.
  function getStableTokenPriceWithScale() external view returns (uint256);

  /// @notice Preview the result of deposit.
  /// @param tokenIn The address of input token.
  /// @param amount The amount of input tokens to deposit.
  /// @return amountSharesOut The amount of pool shares should receive.
  function previewDeposit(address tokenIn, uint256 amount) external view returns (uint256 amountSharesOut);

  /// @notice Preview the result of redeem.
  /// @param amountSharesToRedeem The amount of pool shares to redeem.
  /// @return amountYieldOut The amount of yield token should receive.
  /// @return amountStableOut The amount of stable token should receive.
  function previewRedeem(
    uint256 amountSharesToRedeem
  ) external view returns (uint256 amountYieldOut, uint256 amountStableOut);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Deposit token.
  /// @param receiver The address of pool shares recipient.
  /// @param tokenIn The address of input token.
  /// @param amountTokenToDeposit The amount of input tokens to deposit.
  /// @param minSharesOut The minimum amount of pool shares should receive.
  /// @return amountSharesOut The amount of pool shares received.
  function deposit(
    address receiver,
    address tokenIn,
    uint256 amountTokenToDeposit,
    uint256 minSharesOut
  ) external returns (uint256 amountSharesOut);

  /// @notice Request redeem.
  /// @param shares The amount of shares to request.
  function requestRedeem(uint256 shares) external;

  /// @notice Redeem pool shares.
  /// @param receiver The address of token recipient.
  /// @param shares The amount of pool shares to redeem.
  /// @return amountYieldOut The amount of yield token should received.
  /// @return amountStableOut The amount of stable token should received.
  function redeem(address receiver, uint256 shares) external returns (uint256 amountYieldOut, uint256 amountStableOut);

  /// @notice Redeem pool shares instantly with withdraw fee.
  /// @param receiver The address of token recipient.
  /// @param shares The amount of pool shares to redeem.
  /// @return amountYieldOut The amount of yield token should received.
  /// @return amountStableOut The amount of stable token should received.
  function instantRedeem(address receiver, uint256 shares) external returns (uint256 amountYieldOut, uint256 amountStableOut);

  /// @notice Rebalance all positions in the given tick.
  /// @param pool The address of pool to rebalance.
  /// @param tick The index of tick to rebalance.
  /// @param tokenIn The address of token to rebalance.
  /// @param maxAmount The maximum amount of input token to rebalance.
  /// @param minBaseOut The minimum amount of collateral tokens should receive.
  /// @return tokenUsed The amount of input token used to rebalance.
  /// @return baseOut The amount of collateral tokens rebalanced.
  function rebalance(
    address pool,
    int16 tick,
    address tokenIn,
    uint256 maxAmount,
    uint256 minBaseOut
  ) external returns (uint256 tokenUsed, uint256 baseOut);

  /// @notice Rebalance all possible ticks.
  /// @param pool The address of pool to rebalance.
  /// @param tokenIn The address of token to rebalance.
  /// @param maxAmount The maximum amount of input token to rebalance.
  /// @param minBaseOut The minimum amount of collateral tokens should receive.
  /// @return tokenUsed The amount of input token used to rebalance.
  /// @return baseOut The amount of collateral tokens rebalanced.
  function rebalance(
    address pool,
    address tokenIn,
    uint256 maxAmount,
    uint256 minBaseOut
  ) external returns (uint256 tokenUsed, uint256 baseOut);

  /// @notice Liquidate all possible ticks.
  /// @param pool The address of pool to rebalance.
  /// @param tokenIn The address of token to rebalance.
  /// @param maxAmount The maximum amount of input token to rebalance.
  /// @param minBaseOut The minimum amount of collateral tokens should receive.
  /// @return tokenUsed The amount of input token used to rebalance.
  /// @return baseOut The amount of collateral tokens rebalanced.
  function liquidate(
    address pool,
    address tokenIn,
    uint256 maxAmount,
    uint256 minBaseOut
  ) external returns (uint256 tokenUsed, uint256 baseOut);

  /// @notice Arbitrage between yield token and stable token.
  /// @param srcToken The address of source token.
  /// @param amountIn The amount of source token to use.
  /// @param receiver The address of bonus receiver.
  /// @param data The hook data to `onSwap`.
  /// @return amountOut The amount of target token swapped.
  /// @return bonusOut The amount of bonus token.
  function arbitrage(
    address srcToken,
    uint256 amountIn,
    address receiver,
    bytes calldata data
  ) external returns (uint256 amountOut, uint256 bonusOut);
}
