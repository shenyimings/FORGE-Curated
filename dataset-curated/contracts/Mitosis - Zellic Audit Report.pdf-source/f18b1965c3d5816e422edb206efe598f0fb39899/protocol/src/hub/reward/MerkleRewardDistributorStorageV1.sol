// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ITreasury } from '../../interfaces/hub/reward/ITreasury.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { StdError } from '../../lib/StdError.sol';

abstract contract MerkleRewardDistributorStorageV1 {
  using ERC7201Utils for string;

  struct Stage {
    uint256 nonce;
    bytes32 root;
    address[] rewards;
    uint256[] amounts;
    mapping(address receiver => mapping(address matrixVault => bool)) claimed;
  }

  struct StorageV1 {
    uint256 lastStage;
    ITreasury treasury;
    mapping(uint256 stage => Stage) stages;
    mapping(address reward => uint256 amount) reservedRewardAmounts;
  }

  string private constant _NAMESPACE = 'mitosis.storage.MerkleRewardDistributorStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}
