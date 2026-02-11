// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';

import { VLFVault } from './VLFVault.sol';

/**
 * @title VLFVaultBasic
 * @notice Basic implementation of a VLFVault that simply inherits the VLFVault contract
 */
contract VLFVaultBasic is VLFVault {
  constructor() {
    _disableInitializers();
  }

  function initialize(address assetManager_, IERC20Metadata asset_, string memory name, string memory symbol)
    external
    initializer
  {
    __VLFVault_init(assetManager_, asset_, name, symbol);
  }
}
