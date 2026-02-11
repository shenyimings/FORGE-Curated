// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.23 <0.9.0;

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';

interface IVLFVaultFactory {
  enum VLFVaultType {
    Unset,
    Basic,
    Capped
  }

  struct BasicVLFVaultInitArgs {
    address assetManager;
    IERC20Metadata asset;
    string name;
    string symbol;
  }

  struct CappedVLFVaultInitArgs {
    address assetManager;
    IERC20Metadata asset;
    string name;
    string symbol;
  }

  event VLFVaultTypeInitialized(VLFVaultType indexed vaultType, address indexed beacon);
  event VLFVaultCreated(VLFVaultType indexed vaultType, address indexed instance, bytes initArgs);
  event VLFVaultMigrated(VLFVaultType indexed from, VLFVaultType indexed to, address indexed instance);
  event BeaconCalled(address indexed caller, VLFVaultType indexed vaultType, bytes data, bool success, bytes ret);

  error IVLFVaultFactory__AlreadyInitialized();
  error IVLFVaultFactory__NotInitialized();
  error IVLFVaultFactory__NotAnInstance();
  error IVLFVaultFactory__InvalidVLFVaultType();
  error IVLFVaultFactory__CallBeaconFailed(bytes ret);

  function beacon(uint8 t) external view returns (address);
  function isInstance(address instance) external view returns (bool);
  function isInstance(uint8 t, address instance) external view returns (bool);
  function instances(uint8 t, uint256 index) external view returns (address);
  function instances(uint8 t, uint256[] memory indexes) external view returns (address[] memory);
  function instancesLength(uint8 t) external view returns (uint256);
  function vlfVaultTypeInitialized(uint8 t) external view returns (bool);

  function callBeacon(uint8 t, bytes calldata data) external returns (bytes memory);
  function create(uint8 t, bytes calldata args) external returns (address);
  function migrate(uint8 from, uint8 to, address instance, bytes calldata data) external;
}
