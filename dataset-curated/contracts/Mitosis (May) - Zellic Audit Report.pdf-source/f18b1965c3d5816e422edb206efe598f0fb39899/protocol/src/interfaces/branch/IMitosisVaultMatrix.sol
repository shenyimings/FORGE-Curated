// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum MatrixAction {
  None,
  FetchMatrix
}

interface IMitosisVaultMatrix {
  //=========== NOTE: EVENT DEFINITIONS ===========//

  event MatrixInitialized(address hubMatrixVault, address asset);
  event MatrixDepositedWithSupply(
    address indexed asset, address indexed to, address indexed hubMatrixVault, uint256 amount
  );
  event MatrixAllocated(address indexed hubMatrixVault, uint256 amount);
  event MatrixDeallocated(address indexed hubMatrixVault, uint256 amount);
  event MatrixFetched(address indexed hubMatrixVault, uint256 amount);
  event MatrixReturned(address indexed hubMatrixVault, uint256 amount);

  event MatrixYieldSettled(address indexed hubMatrixVault, uint256 amount);
  event MatrixLossSettled(address indexed hubMatrixVault, uint256 amount);
  event MatrixExtraRewardsSettled(address indexed hubMatrixVault, address indexed reward, uint256 amount);

  event MatrixHalted(address indexed hubMatrixVault, MatrixAction action);
  event MatrixResumed(address indexed hubMatrixVault, MatrixAction action);

  event MatrixStrategyExecutorSet(address indexed hubMatrixVault, address indexed strategyExecutor);

  //=========== NOTE: ERROR DEFINITIONS ===========//

  error IMitosisVaultMatrix__MatrixNotInitialized(address hubMatrixVault);
  error IMitosisVaultMatrix__MatrixAlreadyInitialized(address hubMatrixVault);
  error IMitosisVaultMatrix__InvalidMatrixVault(address hubMatrixVault, address asset);
  error IMitosisVaultMatrix__StrategyExecutorNotDrained(address hubMatrixVault, address strategyExecutor);

  //=========== NOTE: View functions ===========//

  function isMatrixInitialized(address hubMatrixVault) external view returns (bool);
  function availableMatrix(address hubMatrixVault) external view returns (uint256);
  function matrixStrategyExecutor(address hubMatrixVault) external view returns (address);

  //=========== NOTE: Asset ===========//

  function depositWithSupplyMatrix(address asset, address to, address hubMatrixVault, uint256 amount) external;

  //=========== NOTE: Matrix ===========//

  function initializeMatrix(address hubMatrixVault, address asset) external;

  function allocateMatrix(address hubMatrixVault, uint256 amount) external;
  function deallocateMatrix(address hubMatrixVault, uint256 amount) external;

  function fetchMatrix(address hubMatrixVault, uint256 amount) external;
  function returnMatrix(address hubMatrixVault, uint256 amount) external;

  function settleMatrixYield(address hubMatrixVault, uint256 amount) external;
  function settleMatrixLoss(address hubMatrixVault, uint256 amount) external;
  function settleMatrixExtraRewards(address hubMatrixVault, address reward, uint256 amount) external;

  //=========== NOTE: Ownable ===========//

  function setMatrixStrategyExecutor(address hubMatrixVault, address strategyExecutor) external;
}
