// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IStrategyExecutor } from '../../../interfaces/branch/strategy/IStrategyExecutor.sol';
import { ERC7201Utils } from '../../../lib/ERC7201Utils.sol';

abstract contract ManagerWithMerkleVerificationStorageV1 {
  using ERC7201Utils for string;

  struct StorageV1 {
    mapping(address strategyExecutor => mapping(address strategist => bytes32 manageRoot)) manageRoot;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ManagerWithMerkleVerificationStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}
