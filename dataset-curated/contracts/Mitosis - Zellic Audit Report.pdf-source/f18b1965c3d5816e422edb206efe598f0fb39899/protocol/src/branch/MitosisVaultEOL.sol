// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';

import { IMitosisVaultEntrypoint } from '../interfaces/branch/IMitosisVaultEntrypoint.sol';
import { IMitosisVaultEOL, EOLAction } from '../interfaces/branch/IMitosisVaultEOL.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { Pausable } from '../lib/Pausable.sol';
import { StdError } from '../lib/StdError.sol';

abstract contract MitosisVaultEOL is IMitosisVaultEOL, Pausable, Ownable2StepUpgradeable {
  using ERC7201Utils for string;

  struct EOLInfo {
    bool initialized;
    address asset;
    mapping(EOLAction => bool) isHalted;
  }

  struct EOLStorageV1 {
    mapping(address hubEOLVault => EOLInfo) eols;
  }

  string private constant _NAMESPACE = 'mitosis.storage.MitosisVault.EOL.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getEOLStorageV1() private view returns (EOLStorageV1 storage $) {
    bytes32 slot = _slot;
    assembly {
      $.slot := slot
    }
  }

  //=========== NOTE: View ===========//

  function isEOLActionHalted(address hubEOLVault, EOLAction action) external view returns (bool) {
    return _isEOLHalted(_getEOLStorageV1(), hubEOLVault, action);
  }

  function isEOLInitialized(address hubEOLVault) external view returns (bool) {
    return _isEOLInitialized(_getEOLStorageV1(), hubEOLVault);
  }

  //=========== NOTE: Asset ===========//

  function _deposit(address asset, address to, uint256 amount) internal virtual;

  function _assertAssetInitialized(address asset) internal view virtual;

  function entrypoint() public view virtual returns (address);

  function depositWithSupplyEOL(address asset, address to, address hubEOLVault, uint256 amount) external whenNotPaused {
    _deposit(asset, to, amount);

    EOLStorageV1 storage $ = _getEOLStorageV1();
    _assertEOLInitialized($, hubEOLVault);
    require(asset == $.eols[hubEOLVault].asset, IMitosisVaultEOL__InvalidEOLVault(hubEOLVault, asset));

    IMitosisVaultEntrypoint(entrypoint()).depositWithSupplyEOL(asset, to, hubEOLVault, amount);

    emit EOLDepositedWithSupply(asset, to, hubEOLVault, amount);
  }

  //=========== NOTE: EOL Lifecycle ===========//

  function initializeEOL(address hubEOLVault, address asset) external whenNotPaused {
    require(entrypoint() == _msgSender(), StdError.Unauthorized());

    EOLStorageV1 storage $ = _getEOLStorageV1();
    _assertEOLNotInitialized($, hubEOLVault);
    _assertAssetInitialized(asset);

    $.eols[hubEOLVault].initialized = true;
    $.eols[hubEOLVault].asset = asset;

    emit EOLInitialized(hubEOLVault, asset);
  }

  //=========== NOTE: INTERNAL FUNCTIONS ===========//

  function _isEOLHalted(EOLStorageV1 storage $, address hubEOLVault, EOLAction action) internal view returns (bool) {
    return $.eols[hubEOLVault].isHalted[action];
  }

  function _haltEOL(EOLStorageV1 storage $, address hubEOLVault, EOLAction action) internal {
    $.eols[hubEOLVault].isHalted[action] = true;
    emit EOLHalted(hubEOLVault, action);
  }

  function _resumeEOL(EOLStorageV1 storage $, address hubEOLVault, EOLAction action) internal {
    $.eols[hubEOLVault].isHalted[action] = false;
    emit EOLResumed(hubEOLVault, action);
  }

  function _isEOLInitialized(EOLStorageV1 storage $, address hubEOLVault) internal view returns (bool) {
    return $.eols[hubEOLVault].initialized;
  }

  function _assertEOLInitialized(EOLStorageV1 storage $, address hubEOLVault) internal view {
    require(_isEOLInitialized($, hubEOLVault), IMitosisVaultEOL__EOLNotInitialized(hubEOLVault));
  }

  function _assertEOLNotInitialized(EOLStorageV1 storage $, address hubEOLVault) internal view {
    require(!_isEOLInitialized($, hubEOLVault), IMitosisVaultEOL__EOLAlreadyInitialized(hubEOLVault));
  }
}
