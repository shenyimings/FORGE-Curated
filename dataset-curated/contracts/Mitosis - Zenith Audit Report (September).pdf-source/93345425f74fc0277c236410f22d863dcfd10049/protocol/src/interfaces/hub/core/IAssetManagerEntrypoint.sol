// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IAssetManager } from './IAssetManager.sol';

/**
 * @title IAssetManagerEntrypoint
 * @notice Interface for the Asset Manager Entrypoint, which serves as a bridge between the Asset Manager and branch chains
 * @dev This interface defines the methods for cross-chain asset management operations
 */
interface IAssetManagerEntrypoint {
  /**
   * @notice Returns the address of the associated Asset Manager contract
   */
  function assetManager() external view returns (IAssetManager);

  /**
   * @notice Retrieves the Hyperlane domain for a given chain ID
   * @param chainId The ID of the chain to query
   * @return The Hyperlane domain associated with the given chain ID
   */
  function branchDomain(uint256 chainId) external view returns (uint32);

  /**
   * @notice Gets the address of the branch vault for a specific chain
   * @param chainId The ID of the chain to query
   * @return The address of the branch MitosisVault on the specified chain
   */
  function branchMitosisVault(uint256 chainId) external view returns (address);

  /**
   * @notice Retrieves the address of the branch entrypoint for a given chain
   * @param chainId The ID of the chain to query
   * @return The address of the branch MitosisVaultEntrypoint on the specified chain
   */
  function branchMitosisVaultEntrypoint(uint256 chainId) external view returns (address);

  /**
   * @notice Quotes the gas fee for initializing an asset on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param branchAsset The address of the asset on the branch chain
   * @return The gas fee required for the operation
   */
  function quoteInitializeAsset(uint256 chainId, address branchAsset) external view returns (uint256);

  /**
   * @notice Quotes the gas fee for initializing a VLF on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param vlfVault The address of the VLFVault
   * @param branchAsset The address of the associated asset on the branch chain
   * @return The gas fee required for the operation
   */
  function quoteInitializeVLF(uint256 chainId, address vlfVault, address branchAsset) external view returns (uint256);

  /**
   * @notice Quotes the gas fee for withdrawing assets from a branch chain
   * @param chainId The ID of the branch chain
   * @param branchAsset The address of the asset on the branch chain
   * @param to The address that will receive the withdrawn assets
   * @param amount The amount of assets to withdraw
   * @return The gas fee required for the operation
   */
  function quoteWithdraw(uint256 chainId, address branchAsset, address to, uint256 amount)
    external
    view
    returns (uint256);

  /**
   * @notice Quotes the gas fee for allocating assets to a VLF on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param vlfVault The address of the VLFVault
   * @param amount The amount of assets to allocate
   * @return The gas fee required for the operation
   */
  function quoteAllocateVLF(uint256 chainId, address vlfVault, uint256 amount) external view returns (uint256);

  /**
   * @notice Initializes an asset on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param branchAsset The address of the asset on the branch chain
   */
  function initializeAsset(uint256 chainId, address branchAsset) external payable;

  /**
   * @notice Initializes a VLF on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param vlfVault The address of the VLFVault
   * @param branchAsset The address of the associated asset on the branch chain
   */
  function initializeVLF(uint256 chainId, address vlfVault, address branchAsset) external payable;

  /**
   * @notice Initiates a withdrawal of assets from a branch chain
   * @param chainId The ID of the branch chain
   * @param branchAsset The address of the asset on the branch chain
   * @param to The address that will receive the withdrawn assets
   * @param amount The amount of assets to withdraw
   */
  function withdraw(uint256 chainId, address branchAsset, address to, uint256 amount) external payable;

  /**
   * @notice Allocates assets to the StrategyExecutor for VLF on branch chain
   * @param chainId The ID of the branch chain
   * @param vlfVault The address of the VLFVault
   * @param amount The amount of assets to allocate
   */
  function allocateVLF(uint256 chainId, address vlfVault, uint256 amount) external payable;
}
