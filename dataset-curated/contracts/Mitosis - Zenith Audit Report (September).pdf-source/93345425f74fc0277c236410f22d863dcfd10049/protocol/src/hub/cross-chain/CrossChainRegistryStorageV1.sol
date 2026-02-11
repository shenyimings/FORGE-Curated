// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';

contract CrossChainRegistryStorageV1 {
  using ERC7201Utils for string;

  struct ChainInfo {
    string name;
    // Branch info
    uint32 hplDomain;
    address mitosisVault;
    address mitosisVaultEntrypoint;
    address governanceEntrypoint;
    bool mitosisVaultEntrypointEnrolled;
    bool governanceEntrypointEnrolled;
  }

  struct HyperlaneInfo {
    uint256 chainId;
  }

  struct StorageV1 {
    uint256[] chainIds;
    uint32[] hplDomains;
    mapping(uint256 chainId => ChainInfo) chains;
    mapping(uint32 hplDomain => HyperlaneInfo) hyperlanes;
  }

  string private constant _NAMESPACE = 'mitosis.storage.CrossChainRegistryStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}
