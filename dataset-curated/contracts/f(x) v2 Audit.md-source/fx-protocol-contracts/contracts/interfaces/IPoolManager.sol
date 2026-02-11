// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPoolManager {
  /**********
   * Events *
   **********/
  
  /// @notice Register a new pool.
  /// @param pool The address of fx pool.
  event RegisterPool(address indexed pool);

  /// @notice Emitted when the reward splitter contract is updated.
  /// @param pool The address of fx pool.
  /// @param oldSplitter The address of previous reward splitter contract.
  /// @param newSplitter The address of current reward splitter contract.
  event UpdateRewardSplitter(address indexed pool, address indexed oldSplitter, address indexed newSplitter);

  /// @notice Emitted when the threshold for permissionless liquidate/rebalance is updated.
  /// @param oldThreshold The value of previous threshold.
  /// @param newThreshold The value of current threshold.
  event UpdatePermissionedLiquidationThreshold(uint256 oldThreshold, uint256 newThreshold);

  /// @notice Emitted when token rate is updated.
  /// @param scalar The token scalar to reach 18 decimals.
  /// @param provider The address of token rate provider.
  event UpdateTokenRate(address indexed token, uint256 scalar, address provider);

  /// @notice Emitted when pool capacity is updated.
  /// @param pool The address of fx pool.
  /// @param collateralCapacity The capacity for collateral token.
  /// @param debtCapacity The capacity for debt token.
  event UpdatePoolCapacity(address indexed pool, uint256 collateralCapacity, uint256 debtCapacity);

  /// @notice Emitted when position is updated.
  /// @param pool The address of pool where the position belongs to.
  /// @param position The id of the position.
  /// @param deltaColls The amount of collateral token changes.
  /// @param deltaDebts The amount of debt token changes.
  /// @param protocolFees The amount of protocol fees charges.
  event Operate(
    address indexed pool,
    uint256 indexed position,
    int256 deltaColls,
    int256 deltaDebts,
    uint256 protocolFees
  );
  
  /// @notice Emitted when redeem happened.
  /// @param pool The address of pool redeemed.
  /// @param colls The amount of collateral tokens redeemed.
  /// @param debts The amount of debt tokens redeemed.
  /// @param protocolFees The amount of protocol fees charges.
  event Redeem(address indexed pool, uint256 colls, uint256 debts, uint256 protocolFees);

  /// @notice Emitted when rebalance for a tick happened.
  /// @param pool The address of pool rebalanced.
  /// @param tick The index of tick rebalanced.
  /// @param colls The amount of collateral tokens rebalanced.
  /// @param fxUSDDebts The amount of fxUSD rebalanced.
  /// @param stableDebts The amount of stable token (a.k.a USDC) rebalanced.
  event RebalanceTick(address indexed pool, int16 indexed tick, uint256 colls, uint256 fxUSDDebts, uint256 stableDebts);

  /// @notice Emitted when rebalance happened.
  /// @param pool The address of pool rebalanced.
  /// @param colls The amount of collateral tokens rebalanced.
  /// @param fxUSDDebts The amount of fxUSD rebalanced.
  /// @param stableDebts The amount of stable token (a.k.a USDC) rebalanced.
  event Rebalance(address indexed pool, uint256 colls, uint256 fxUSDDebts, uint256 stableDebts);

  /// @notice Emitted when liquidate happened.
  /// @param pool The address of pool liquidated.
  /// @param colls The amount of collateral tokens liquidated.
  /// @param fxUSDDebts The amount of fxUSD liquidated.
  /// @param stableDebts The amount of stable token (a.k.a USDC) liquidated.
  event Liquidate(address indexed pool, uint256 colls, uint256 fxUSDDebts, uint256 stableDebts);

  /// @notice Emitted when someone harvest pending rewards.
  /// @param caller The address of caller.
  /// @param amountRewards The amount of total harvested rewards.
  /// @param amountFunding The amount of total harvested funding.
  /// @param performanceFee The amount of harvested rewards distributed to protocol revenue.
  /// @param harvestBounty The amount of harvested rewards distributed to caller as harvest bounty.
  event Harvest(
    address indexed caller,
    address indexed pool,
    uint256 amountRewards,
    uint256 amountFunding,
    uint256 performanceFee,
    uint256 harvestBounty
  );

  /*************************
   * Public View Functions *
   *************************/
  
  /// @notice The address of fxUSD.
  function fxUSD() external view returns (address);

  /// @notice The address of FxUSDSave.
  function fxBASE() external view returns (address);

  /// @notice The address of `PegKeeper`.
  function pegKeeper() external view returns (address);

  /// @notice The address of reward splitter.
  function rewardSplitter(address pool) external view returns (address);

  /****************************
   * Public Mutated Functions *
   ****************************/
  
  /// @notice Open a new position or operate on an old position.
  /// @param pool The address of pool to operate.
  /// @param positionId The id of the position. If `positionId=0`, it means we need to open a new position.
  /// @param newColl The amount of collateral token to supply (positive value) or withdraw (negative value).
  /// @param newDebt The amount of debt token to borrow (positive value) or repay (negative value).
  /// @return actualPositionId The id of this position.
  function operate(
    address pool,
    uint256 positionId,
    int256 newColl,
    int256 newDebt
  ) external returns (uint256 actualPositionId);

  /// @notice Redeem debt tokens to get collateral tokens.
  /// @param pool The address of pool to redeem.
  /// @param debts The amount of debt tokens to redeem.
  /// @param minColls The minimum amount of collateral tokens should redeem.
  /// @return colls The amount of collateral tokens redeemed.
  function redeem(address pool, uint256 debts, uint256 minColls) external returns (uint256 colls);

  /// @notice Rebalance all positions in the given tick.
  /// @param pool The address of pool to rebalance.
  /// @param receiver The address of recipient for rebalanced tokens.
  /// @param tick The index of tick to rebalance.
  /// @param maxFxUSD The maximum amount of fxUSD to rebalance.
  /// @param maxStable The maximum amount of stable token (a.k.a USDC) to rebalance.
  /// @return colls The amount of collateral tokens rebalanced.
  /// @return fxUSDUsed The amount of fxUSD used to rebalance.
  /// @return stableUsed The amount of stable token used to rebalance.
  function rebalance(
    address pool,
    address receiver,
    int16 tick,
    uint256 maxFxUSD,
    uint256 maxStable
  ) external returns (uint256 colls, uint256 fxUSDUsed, uint256 stableUsed);

  /// @notice Rebalance all positions in the given tick.
  /// @param pool The address of pool to rebalance.
  /// @param receiver The address of recipient for rebalanced tokens.
  /// @param maxFxUSD The maximum amount of fxUSD to rebalance.
  /// @param maxStable The maximum amount of stable token (a.k.a USDC) to rebalance.
  /// @return colls The amount of collateral tokens rebalanced.
  /// @return fxUSDUsed The amount of fxUSD used to rebalance.
  /// @return stableUsed The amount of stable token used to rebalance.
  function rebalance(
    address pool,
    address receiver,
    uint256 maxFxUSD,
    uint256 maxStable
  ) external returns (uint256 colls, uint256 fxUSDUsed, uint256 stableUsed);

  /// @notice Liquidate a given position.
  /// @param pool The address of pool to liquidate.
  /// @param receiver The address of recipient for liquidated tokens.
  /// @param maxFxUSD The maximum amount of fxUSD to liquidate.
  /// @param maxStable The maximum amount of stable token (a.k.a USDC) to liquidate.
  /// @return colls The amount of collateral tokens liquidated.
  /// @return fxUSDUsed The amount of fxUSD used to liquidate.
  /// @return stableUsed The amount of stable token used to liquidate.
  function liquidate(
    address pool,
    address receiver,
    uint256 maxFxUSD,
    uint256 maxStable
  ) external returns (uint256 colls, uint256 fxUSDUsed, uint256 stableUsed);

  /// @notice Harvest pending rewards of the given pool.
  /// @param pool The address of pool to harvest.
  /// @return amountRewards The amount of rewards harvested.
  /// @return amountFunding The amount of funding harvested.
  function harvest(address pool) external returns (uint256 amountRewards, uint256 amountFunding);
}
