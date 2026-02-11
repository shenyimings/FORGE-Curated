// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';

interface IMatrixVaultFactory {
  enum VaultType {
    Unset,
    Basic,
    Capped
  }

  struct BasicVaultInitArgs {
    address owner;
    address assetManager;
    IERC20Metadata asset;
    string name;
    string symbol;
  }

  struct CappedVaultInitArgs {
    address owner;
    address assetManager;
    IERC20Metadata asset;
    string name;
    string symbol;
  }

  event VaultTypeInitialized(VaultType indexed vaultType, address indexed beacon);
  event MatrixVaultCreated(VaultType indexed vaultType, address indexed instance, bytes initArgs);
  event MatrixVaultMigrated(VaultType indexed from, VaultType indexed to, address indexed instance);
  event BeaconCalled(address indexed caller, VaultType indexed vaultType, bytes data, bool success, bytes ret);

  error IMatrixVaultFactory__AlreadyInitialized();
  error IMatrixVaultFactory__NotInitialized();
  error IMatrixVaultFactory__NotAnInstance();
  error IMatrixVaultFactory__InvalidVaultType();
  error IMatrixVaultFactory__CallBeaconFailed(bytes ret);

  function beacon(VaultType t) external view returns (address);
  function isInstance(address instance) external view returns (bool);
  function isInstance(VaultType t, address instance) external view returns (bool);
  function instances(VaultType t, uint256 index) external view returns (address);
  function instances(VaultType t, uint256[] memory indexes) external view returns (address[] memory);
  function instancesLength(VaultType t) external view returns (uint256);
  function vaultTypeInitialized(VaultType t) external view returns (bool);

  function callBeacon(VaultType t, bytes calldata data) external returns (bytes memory);
  function create(VaultType t, bytes calldata args) external returns (address);
  function migrate(VaultType from, VaultType to, address instance, bytes calldata data) external;
}
