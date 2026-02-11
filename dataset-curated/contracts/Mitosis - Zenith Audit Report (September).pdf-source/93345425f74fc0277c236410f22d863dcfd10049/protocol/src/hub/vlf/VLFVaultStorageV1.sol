// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ContextUpgradeable } from '@ozu/utils/ContextUpgradeable.sol';

import { IAssetManager } from '../../interfaces/hub/core/IAssetManager.sol';
import { IVLFVaultStorageV1 } from '../../interfaces/hub/vlf/IVLFVault.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { StdError } from '../../lib/StdError.sol';

contract VLFVaultStorageV1 is IVLFVaultStorageV1, ContextUpgradeable {
  using ERC7201Utils for string;

  struct StorageV1 {
    address asset;
    string name;
    string symbol;
    uint8 decimals;
    IAssetManager assetManager;
  }

  string private constant _NAMESPACE = 'mitosis.storage.VLFVaultStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // ============================ NOTE: VIEW FUNCTIONS ============================ //

  function assetManager() external view returns (address) {
    return address(_getStorageV1().assetManager);
  }

  function reclaimQueue() external view returns (address) {
    return address(_getStorageV1().assetManager.reclaimQueue());
  }

  // ============================ NOTE: MUTATIVE FUNCTIONS ============================ //

  function _setAssetManager(StorageV1 storage $, address assetManager_) internal {
    require(assetManager_.code.length > 0, StdError.InvalidAddress('AssetManager'));

    // Verify ReclaimQueue exists
    address reclaimQueueAddr = IAssetManager(assetManager_).reclaimQueue();
    require(reclaimQueueAddr.code.length > 0, StdError.InvalidAddress('ReclaimQueue'));

    $.assetManager = IAssetManager(assetManager_);

    emit AssetManagerSet(assetManager_);
  }

  // ============================ NOTE: MUTATIVE FUNCTIONS ============================ //

  function _assertOnlyAssetManager(StorageV1 storage $) internal view {
    require(_msgSender() == address($.assetManager), StdError.Unauthorized());
  }

  function _assertOnlyReclaimQueue(StorageV1 storage $) internal view {
    require(_msgSender() == $.assetManager.reclaimQueue(), StdError.Unauthorized());
  }
}
