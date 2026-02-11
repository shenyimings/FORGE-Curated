// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPool {
  /**********
   * Events *
   **********/

  /// @notice Emitted when price oracle is updated.
  /// @param oldOracle The previous address of price oracle.
  /// @param newOracle The current address of price oracle.
  event UpdatePriceOracle(address oldOracle, address newOracle);

  /// @notice Emitted when borrow status is updated.
  /// @param status The updated borrow status.
  event UpdateBorrowStatus(bool status);

  /// @notice Emitted when redeem status is updated.
  /// @param status The updated redeem status.
  event UpdateRedeemStatus(bool status);

  /// @notice Emitted when debt ratio range is updated.
  /// @param minDebtRatio The current value of minimum debt ratio, multiplied by 1e18.
  /// @param maxDebtRatio The current value of maximum debt ratio, multiplied by 1e18.
  event UpdateDebtRatioRange(uint256 minDebtRatio, uint256 maxDebtRatio);

  /// @notice Emitted when max redeem ratio per tick is updated.
  /// @param ratio The current value of max redeem ratio per tick, multiplied by 1e9.
  event UpdateMaxRedeemRatioPerTick(uint256 ratio);

  /// @notice Emitted when the rebalance ratio is updated.
  /// @param debtRatio The current value of rebalance debt ratio, multiplied by 1e18.
  /// @param bonusRatio The current value of rebalance bonus ratio, multiplied by 1e9.
  event UpdateRebalanceRatios(uint256 debtRatio, uint256 bonusRatio);

  /// @notice Emitted when the liquidate ratio is updated.
  /// @param debtRatio The current value of liquidate debt ratio, multiplied by 1e18.
  /// @param bonusRatio The current value of liquidate bonus ratio, multiplied by 1e9.
  event UpdateLiquidateRatios(uint256 debtRatio, uint256 bonusRatio);

  /// @notice Emitted when position is updated.
  /// @param position The index of this position.
  /// @param tick The index of tick, this position belongs to.
  /// @param collShares The amount of collateral shares in this position.
  /// @param debtShares The amount of debt shares in this position.
  /// @param price The price used for this operation.
  event PositionSnapshot(uint256 position, int16 tick, uint256 collShares, uint256 debtShares, uint256 price);

  /// @notice Emitted when tick moved due to rebalance, liquidate or redeem.
  /// @param oldTick The index of the previous tick.
  /// @param newTick The index of the current tick.
  /// @param collShares The amount of collateral shares added to new tick.
  /// @param debtShares The amount of debt shares added to new tick.
  /// @param price The price used for this operation.
  event TickMovement(int16 oldTick, int16 newTick, uint256 collShares, uint256 debtShares, uint256 price);

  /// @notice Emitted when debt index increase.
  event DebtIndexSnapshot(uint256 index);

  /// @notice Emitted when collateral index increase.
  event CollateralIndexSnapshot(uint256 index);

  /***********
   * Structs *
   ***********/

  /// @dev The result for liquidation.
  /// @param rawColls The amount of collateral tokens liquidated.
  /// @param rawDebts The amount of debt tokens liquidated.
  /// @param bonusRawColls The amount of bonus collateral tokens given.
  /// @param bonusFromReserve The amount of bonus collateral tokens coming from reserve pool.
  struct LiquidateResult {
    uint256 rawColls;
    uint256 rawDebts;
    uint256 bonusRawColls;
    uint256 bonusFromReserve;
  }

  /// @dev The result for rebalance.
  /// @param rawColls The amount of collateral tokens rebalanced.
  /// @param rawDebts The amount of debt tokens rebalanced.
  /// @param bonusRawColls The amount of bonus collateral tokens given.
  struct RebalanceResult {
    uint256 rawColls;
    uint256 rawDebts;
    uint256 bonusRawColls;
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @notice The address of fxUSD.
  function fxUSD() external view returns (address);

  /// @notice The address of `PoolManager` contract.
  function poolManager() external view returns (address);

  /// @notice The address of `PegKeeper` contract.
  function pegKeeper() external view returns (address);

  /// @notice The address of collateral token.
  function collateralToken() external view returns (address);

  /// @notice The address of price oracle.
  function priceOracle() external view returns (address);

  /// @notice Return whether borrow is paused.
  function isBorrowPaused() external view returns (bool);

  /// @notice Return whether redeem is paused.
  function isRedeemPaused() external view returns (bool);

  /// @notice Return the current top tick with debts.
  function getTopTick() external view returns (int16);

  /// @notice Return the next position id.
  function getNextPositionId() external view returns (uint32);

  /// @notice Return the next tick tree node id.
  function getNextTreeNodeId() external view returns (uint48);

  /// @notice Return the debt ratio range.
  /// @param minDebtRatio The minimum required debt ratio, multiplied by 1e18.
  /// @param maxDebtRatio The minimum allowed debt ratio, multiplied by 1e18.
  function getDebtRatioRange() external view returns (uint256 minDebtRatio, uint256 maxDebtRatio);

  /// @notice Return the maximum redeem percentage per tick, multiplied by 1e9.
  function getMaxRedeemRatioPerTick() external view returns (uint256);

  /// @notice Get `debtRatio` and `bonusRatio` for rebalance.
  /// @return debtRatio The minimum debt ratio to start rebalance, multiplied by 1e18.
  /// @return bonusRatio The bonus ratio during rebalance, multiplied by 1e9.
  function getRebalanceRatios() external view returns (uint256 debtRatio, uint256 bonusRatio);

  /// @notice Get `debtRatio` and `bonusRatio` for liquidate.
  /// @return debtRatio The minimum debt ratio to start liquidate, multiplied by 1e18.
  /// @return bonusRatio The bonus ratio during liquidate, multiplied by 1e9.
  function getLiquidateRatios() external view returns (uint256 debtRatio, uint256 bonusRatio);

  /// @notice Get debt and collateral index.
  /// @return debtIndex The index for debt shares.
  /// @return collIndex The index for collateral shares.
  function getDebtAndCollateralIndex() external view returns (uint256 debtIndex, uint256 collIndex);

  /// @notice Get debt and collateral shares.
  /// @return debtShares The total number of debt shares.
  /// @return collShares The total number of collateral shares.
  function getDebtAndCollateralShares() external view returns (uint256 debtShares, uint256 collShares);

  /// @notice Return the details of the given position.
  /// @param tokenId The id of position to query.
  /// @return rawColls The amount of collateral tokens supplied in this position.
  /// @return rawDebts The amount of debt tokens borrowed in this position.
  function getPosition(uint256 tokenId) external view returns (uint256 rawColls, uint256 rawDebts);

  /// @notice Return the debt ratio of the given position.
  /// @param tokenId The id of position to query.
  /// @return debtRatio The debt ratio of this position.
  function getPositionDebtRatio(uint256 tokenId) external view returns (uint256 debtRatio);

  /// @notice The total amount of raw collateral tokens.
  function getTotalRawCollaterals() external view returns (uint256);

  /// @notice The total amount of raw debt tokens.
  function getTotalRawDebts() external view returns (uint256);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Open a new position or operate on an old position.
  /// @param positionId The id of the position. If `positionId=0`, it means we need to open a new position.
  /// @param newRawColl The amount of collateral token to supply (positive value) or withdraw (negative value).
  /// @param newRawColl The amount of debt token to borrow (positive value) or repay (negative value).
  /// @param owner The address of position owner.
  /// @return actualPositionId The id of this position.
  /// @return actualRawColl The actual amount of collateral tokens supplied (positive value) or withdrawn (negative value).
  /// @return actualRawDebt The actual amount of debt tokens borrowed (positive value) or repay (negative value).
  function operate(
    uint256 positionId,
    int256 newRawColl,
    int256 newRawDebt,
    address owner
  ) external returns (uint256 actualPositionId, int256 actualRawColl, int256 actualRawDebt, uint256 protocolFees);

  /// @notice Redeem debt tokens to get collateral tokens.
  /// @param rawDebts The amount of debt tokens to redeem.
  /// @return rawColls The amount of collateral tokens to redeemed.
  function redeem(uint256 rawDebts) external returns (uint256 rawColls);

  /// @notice Rebalance all positions in the given tick.
  /// @param tick The id of tick to rebalance.
  /// @param maxRawDebts The maximum amount of debt tokens to rebalance.
  /// @return result The result of rebalance.
  function rebalance(int16 tick, uint256 maxRawDebts) external returns (RebalanceResult memory result);

  /// @notice Rebalance all ticks in the decreasing order of LTV.
  /// @param maxRawDebts The maximum amount of debt tokens to rebalance.
  /// @return result The result of rebalance.
  function rebalance(uint256 maxRawDebts) external returns (RebalanceResult memory result);

  /// @notice Liquidate all ticks in the decreasing order of LTV.
  /// @param maxRawDebts The maximum amount of debt tokens to liquidate.
  /// @param reservedRawColls The amount of collateral tokens in reserve pool.
  /// @return result The result of liquidate.
  function liquidate(uint256 maxRawDebts, uint256 reservedRawColls) external returns (LiquidateResult memory result);
}
