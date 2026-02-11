// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IMitosisVaultEOL } from './IMitosisVaultEOL.sol';
import { IMitosisVaultMatrix } from './IMitosisVaultMatrix.sol';

enum AssetAction {
  None,
  Deposit
}

interface IMitosisVault is IMitosisVaultMatrix, IMitosisVaultEOL {
  //=========== NOTE: EVENT DEFINITIONS ===========//

  event CapSet(address indexed setter, address indexed asset, uint256 prevMaxCap, uint256 newMaxCap);

  event AssetInitialized(address asset);

  event Deposited(address indexed asset, address indexed to, uint256 amount);
  event Withdrawn(address indexed asset, address indexed to, uint256 amount);

  event EntrypointSet(address entrypoint);

  event AssetHalted(address indexed asset, AssetAction action);
  event AssetResumed(address indexed asset, AssetAction action);

  //=========== NOTE: ERROR DEFINITIONS ===========//

  error IMitosisVault__ExceededCap(address asset, uint256 increasedSupply, uint256 availableCap);

  error IMitosisVault__AssetNotInitialized(address asset);
  error IMitosisVault__AssetAlreadyInitialized(address asset);

  //=========== NOTE: View functions ===========//

  function isAssetInitialized(address asset) external view returns (bool);
  function entrypoint() external view returns (address);

  //=========== NOTE: Asset ===========//

  function initializeAsset(address asset) external;
  function deposit(address asset, address to, uint256 amount) external;
  function withdraw(address asset, address to, uint256 amount) external;

  //=========== NOTE: OWNABLE FUNCTIONS ===========//

  function setEntrypoint(address entrypoint) external;
}
