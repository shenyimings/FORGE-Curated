// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC4626 } from '@oz/interfaces/IERC4626.sol';

/**
 * @title IVLFVaultStorageV1
 * @dev Interface for the storage of VLFVault version 1.
 */
interface IVLFVaultStorageV1 {
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
 * @title IVLFVault
 * @dev Interface for the VLFVault, combining ERC4626 functionality.
 */
interface IVLFVault is IERC4626, IVLFVaultStorageV1 {
  /**
   * @notice Returns the maximum amount of assets that can be deposited from a specific chain
   * @dev This function is only callable by the AssetManager
   * @param receiver The address receiving the shares
   * @param chainId The chain ID where the deposit originates
   * @return maxAssets The maximum deposit amount considering chain-specific bypass rules
   */
  function maxDepositFromChainId(address receiver, uint256 chainId) external view returns (uint256 maxAssets);

  /**
   * @notice Deposit assets with chain-specific soft cap bypass consideration
   * @dev This function is only callable by the AssetManager
   * @param assets The amount of assets to deposit
   * @param receiver The address receiving the shares
   * @param chainId The chain ID where the deposit originates
   * @return shares The amount of shares minted
   */
  function depositFromChainId(uint256 assets, address receiver, uint256 chainId) external returns (uint256 shares);
}
