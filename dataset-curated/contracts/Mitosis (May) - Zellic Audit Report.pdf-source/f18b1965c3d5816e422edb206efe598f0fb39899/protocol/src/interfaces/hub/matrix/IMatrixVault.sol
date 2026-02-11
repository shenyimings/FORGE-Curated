// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC4626 } from '@oz/interfaces/IERC4626.sol';

/**
 * @title IMatrixVaultStorageV1
 * @dev Interface for the storage of MatrixVault version 1.
 */
interface IMatrixVaultStorageV1 {
  /**
   * @notice Emitted when the asset manager is set.
   * @param assetManager_ The address of the new asset manager.
   */
  event AssetManagerSet(address assetManager_);

  /**
   * @notice Returns the address of the current asset manager.
   */
  function assetManager() external view returns (address);
}

/**
 * @title IMatrixVault
 * @dev Interface for the MatrixVault, combining ERC4626 functionality with TWAB snapshots.
 */
interface IMatrixVault is IERC4626, IMatrixVaultStorageV1 { }
