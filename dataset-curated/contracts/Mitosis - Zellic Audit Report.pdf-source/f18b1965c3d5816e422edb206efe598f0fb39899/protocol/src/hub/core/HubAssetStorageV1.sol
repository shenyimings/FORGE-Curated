// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';

abstract contract HubAssetStorageV1 {
  using ERC7201Utils for string;

  struct StorageV1 {
    string name;
    string symbol;
    uint8 decimals;
    address supplyManager;
  }

  string private constant _NAMESPACE = 'mitosis.storage.HubAssetStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}
