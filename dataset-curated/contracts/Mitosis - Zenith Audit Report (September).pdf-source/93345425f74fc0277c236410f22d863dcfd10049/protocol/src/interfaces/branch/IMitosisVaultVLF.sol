// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

enum VLFAction {
  None,
  FetchVLF
}

interface IMitosisVaultVLF {
  //=========== NOTE: EVENT DEFINITIONS ===========//

  event VLFInitialized(address hubVLFVault, address asset);
  event VLFDepositedWithSupply(address indexed asset, address indexed to, address indexed hubVLFVault, uint256 amount);
  event VLFAllocated(address indexed hubVLFVault, uint256 amount);
  event VLFDeallocated(address indexed hubVLFVault, uint256 amount);
  event VLFFetched(address indexed hubVLFVault, uint256 amount);
  event VLFReturned(address indexed hubVLFVault, uint256 amount);

  event VLFYieldSettled(address indexed hubVLFVault, uint256 amount);
  event VLFLossSettled(address indexed hubVLFVault, uint256 amount);
  event VLFExtraRewardsSettled(address indexed hubVLFVault, address indexed reward, uint256 amount);

  event VLFHalted(address indexed hubVLFVault, VLFAction action);
  event VLFResumed(address indexed hubVLFVault, VLFAction action);

  event VLFStrategyExecutorSet(address indexed hubVLFVault, address indexed strategyExecutor);

  //=========== NOTE: ERROR DEFINITIONS ===========//

  error IMitosisVaultVLF__VLFNotInitialized(address hubVLFVault);
  error IMitosisVaultVLF__VLFAlreadyInitialized(address hubVLFVault);
  error IMitosisVaultVLF__InvalidVLF(address hubVLFVault, address asset);
  error IMitosisVaultVLF__StrategyExecutorNotDrained(address hubVLFVault, address strategyExecutor);

  //=========== NOTE: View functions ===========//

  function isVLFInitialized(address hubVLFVault) external view returns (bool);
  function availableVLF(address hubVLFVault) external view returns (uint256);
  function vlfStrategyExecutor(address hubVLFVault) external view returns (address);

  //=========== NOTE: QUOTE FUNCTIONS ===========//

  function quoteDepositWithSupplyVLF(address asset, address to, address hubVLFVault, uint256 amount)
    external
    view
    returns (uint256);

  function quoteDeallocateVLF(address hubVLFVault, uint256 amount) external view returns (uint256);
  function quoteSettleVLFYield(address hubVLFVault, uint256 amount) external view returns (uint256);
  function quoteSettleVLFLoss(address hubVLFVault, uint256 amount) external view returns (uint256);
  function quoteSettleVLFExtraRewards(address hubVLFVault, address reward, uint256 amount)
    external
    view
    returns (uint256);

  //=========== NOTE: Asset ===========//

  function depositWithSupplyVLF(address asset, address to, address hubVLFVault, uint256 amount) external payable;

  //=========== NOTE: VLF ===========//

  function initializeVLF(address hubVLFVault, address asset) external;

  function allocateVLF(address hubVLFVault, uint256 amount) external;
  function deallocateVLF(address hubVLFVault, uint256 amount) external payable;

  function fetchVLF(address hubVLFVault, uint256 amount) external;
  function returnVLF(address hubVLFVault, uint256 amount) external;

  function settleVLFYield(address hubVLFVault, uint256 amount) external payable;
  function settleVLFLoss(address hubVLFVault, uint256 amount) external payable;
  function settleVLFExtraRewards(address hubVLFVault, address reward, uint256 amount) external payable;

  //=========== NOTE: Ownable ===========//

  function setVLFStrategyExecutor(address hubVLFVault, address strategyExecutor) external;
}
