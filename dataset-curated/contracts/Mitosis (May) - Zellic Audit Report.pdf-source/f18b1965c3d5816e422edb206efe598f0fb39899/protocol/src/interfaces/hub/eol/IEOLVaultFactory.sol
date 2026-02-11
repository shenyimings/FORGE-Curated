// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';

interface IEOLVaultFactory {
  enum VaultType {
    Unset,
    Basic
  }

  struct BasicVaultInitArgs {
    address owner;
    IERC20Metadata asset;
    string name;
    string symbol;
  }

  event VaultTypeInitialized(VaultType indexed vaultType, address indexed beacon);
  event EOLVaultCreated(VaultType indexed vaultType, address indexed instance, bytes initArgs);
  event EOLVaultMigrated(VaultType indexed from, VaultType indexed to, address indexed instance);
  event BeaconCalled(address indexed caller, VaultType indexed vaultType, bytes data, bool success, bytes ret);

  error IEOLVaultFactory__AlreadyInitialized();
  error IEOLVaultFactory__NotInitialized();
  error IEOLVaultFactory__NotAnInstance();
  error IEOLVaultFactory__InvalidVaultType();
  error IEOLVaultFactory__CallBeaconFailed(bytes ret);

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
