// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IProtocolFees {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the reserve pool contract is updated.
  /// @param oldReservePool The address of previous reserve pool.
  /// @param newReservePool The address of current reserve pool.
  event UpdateReservePool(address indexed oldReservePool, address indexed newReservePool);

  /// @notice Emitted when the treasury contract is updated.
  /// @param oldTreasury The address of previous treasury contract.
  /// @param newTreasury The address of current treasury contract.
  event UpdateTreasury(address indexed oldTreasury, address indexed newTreasury);

  /// @notice Emitted when the open revenue pool contract is updated.
  /// @param oldPool The address of previous revenue pool contract.
  /// @param newPool The address of current revenue pool contract.
  event UpdateOpenRevenuePool(address indexed oldPool, address indexed newPool);

  /// @notice Emitted when the close revenue pool contract is updated.
  /// @param oldPool The address of previous revenue pool contract.
  /// @param newPool The address of current revenue pool contract.
  event UpdateCloseRevenuePool(address indexed oldPool, address indexed newPool);

  /// @notice Emitted when the misc revenue pool contract is updated.
  /// @param oldPool The address of previous revenue pool contract.
  /// @param newPool The address of current revenue pool contract.
  event UpdateMiscRevenuePool(address indexed oldPool, address indexed newPool);

  /// @notice Emitted when the ratio for treasury is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateRewardsExpenseRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when the ratio for treasury is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateFundingExpenseRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when the ratio for treasury is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateLiquidationExpenseRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when the ratio for harvester is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateHarvesterRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when the flash loan fee ratio is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateFlashLoanFeeRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when the redeem fee ratio is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateRedeemFeeRatio(uint256 oldRatio, uint256 newRatio);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the fee ratio distributed as protocol revenue in funding costs, multiplied by 1e9.
  function getFundingExpenseRatio() external view returns (uint256);

  /// @notice Return the fee ratio distributed as protocol revenue in general rewards, multiplied by 1e9.
  function getRewardsExpenseRatio() external view returns (uint256);

  /// @notice Return the fee ratio distributed as protocol revenue in liquidation/rebalance, multiplied by 1e9.
  function getLiquidationExpenseRatio() external view returns (uint256);

  /// @notice Return the fee ratio distributed to fxBASE in funding costs, multiplied by 1e9.
  function getFundingFxSaveRatio() external view returns (uint256);

  /// @notice Return the fee ratio distributed to fxBASE in general rewards, multiplied by 1e9.
  function getRewardsFxSaveRatio() external view returns (uint256);

  /// @notice Return the fee ratio distributed ad harvester bounty, multiplied by 1e9.
  function getHarvesterRatio() external view returns (uint256);

  /// @notice Return the flash loan fee ratio, multiplied by 1e9.
  function getFlashLoanFeeRatio() external view returns (uint256);

  /// @notice Return the redeem fee ratio, multiplied by 1e9.
  function getRedeemFeeRatio() external view returns (uint256);

  /// @notice Return the address of reserve pool.
  function reservePool() external view returns (address);

  /// @notice Return the address of protocol treasury.
  function treasury() external view returns (address);

  /// @notice Return the address of protocol revenue pool.
  function openRevenuePool() external view returns (address);

  /// @notice Return the address of protocol revenue pool.
  function closeRevenuePool() external view returns (address);

  /// @notice Return the address of protocol revenue pool.
  function miscRevenuePool() external view returns (address);

  /// @notice Return the amount of protocol open fees accumulated by the given pool.
  function accumulatedPoolOpenFees(address pool) external view returns (uint256);

  /// @notice Return the amount of protocol close fees accumulated by the given pool.
  function accumulatedPoolCloseFees(address pool) external view returns (uint256);

  /// @notice Return the amount of protocol misc fees accumulated by the given pool.
  function accumulatedPoolMiscFees(address pool) external view returns (uint256);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Withdraw accumulated pool fee for the given pool lists.
  /// @param pools The list of pool addresses to withdraw.
  function withdrawAccumulatedPoolFee(address[] memory pools) external;
}
