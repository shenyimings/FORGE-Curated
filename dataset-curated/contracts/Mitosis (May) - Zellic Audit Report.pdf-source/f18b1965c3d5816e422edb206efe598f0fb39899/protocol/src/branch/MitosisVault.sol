// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { AssetAction, IMitosisVault } from '../interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../interfaces/branch/IMitosisVaultEntrypoint.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { Pausable } from '../lib/Pausable.sol';
import { StdError } from '../lib/StdError.sol';
import { MitosisVaultEOL } from './MitosisVaultEOL.sol';
import { MitosisVaultMatrix } from './MitosisVaultMatrix.sol';

contract MitosisVault is
  IMitosisVault,
  Pausable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  MitosisVaultMatrix,
  MitosisVaultEOL
{
  using SafeERC20 for IERC20;
  using ERC7201Utils for string;

  struct AssetInfo {
    bool initialized;
    uint256 maxCap;
    uint256 availableCap;
    mapping(AssetAction => bool) isHalted;
  }

  struct StorageV1 {
    IMitosisVaultEntrypoint entrypoint;
    mapping(address asset => AssetInfo) assets;
  }

  string private constant _NAMESPACE = 'mitosis.storage.MitosisVaultStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  //=========== NOTE: INITIALIZATION FUNCTIONS ===========//

  constructor() {
    _disableInitializers();
  }

  fallback() external payable {
    revert StdError.NotSupported();
  }

  receive() external payable {
    revert StdError.NotSupported();
  }

  function initialize(address owner_) public initializer {
    __Pausable_init();
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();
  }

  //=========== NOTE: VIEW FUNCTIONS ===========//

  function maxCap(address asset) external view returns (uint256) {
    return _getStorageV1().assets[asset].maxCap;
  }

  function availableCap(address asset) external view returns (uint256) {
    return _getStorageV1().assets[asset].availableCap;
  }

  function isAssetActionHalted(address asset, AssetAction action) external view returns (bool) {
    return _isHalted(_getStorageV1(), asset, action);
  }

  function isAssetInitialized(address asset) external view returns (bool) {
    return _isAssetInitialized(_getStorageV1(), asset);
  }

  function entrypoint() public view override(IMitosisVault, MitosisVaultMatrix, MitosisVaultEOL) returns (address) {
    return address(_getStorageV1().entrypoint);
  }

  //=========== NOTE: MUTATIVE - ASSET FUNCTIONS ===========//

  function initializeAsset(address asset) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);
    _assertAssetNotInitialized($, asset);

    $.assets[asset].initialized = true;
    emit AssetInitialized(asset);

    // NOTE: we halt deposit and keep the cap at zero by default.
    _haltAsset($, asset, AssetAction.Deposit);
  }

  function deposit(address asset, address to, uint256 amount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _deposit(asset, to, amount);

    $.entrypoint.deposit(asset, to, amount);
    emit Deposited(asset, to, amount);
  }

  function withdraw(address asset, address to, uint256 amount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);
    _assertAssetInitialized(asset);

    IERC20(asset).safeTransfer(to, amount);

    emit Withdrawn(asset, to, amount);
  }

  //=========== NOTE: OWNABLE FUNCTIONS ===========//

  function _authorizeUpgrade(address) internal override onlyOwner { }

  function _authorizePause(address) internal view override onlyOwner { }

  function setEntrypoint(address entrypoint_) external onlyOwner {
    _getStorageV1().entrypoint = IMitosisVaultEntrypoint(entrypoint_);
    emit EntrypointSet(address(entrypoint_));
  }

  function setCap(address asset, uint256 newCap) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    _assertAssetInitialized(asset);

    _setCap($, asset, newCap);
  }

  function haltAsset(address asset, AssetAction action) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    _assertAssetInitialized(asset);
    return _haltAsset($, asset, action);
  }

  function resumeAsset(address asset, AssetAction action) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    _assertAssetInitialized(asset);
    return _resumeAsset($, asset, action);
  }

  //=========== NOTE: INTERNAL FUNCTIONS ===========//

  function _assertOnlyEntrypoint(StorageV1 storage $) internal view {
    require(_msgSender() == address($.entrypoint), StdError.Unauthorized());
  }

  function _assertCapNotExceeded(StorageV1 storage $, address asset, uint256 amount) internal view {
    uint256 available = $.assets[asset].availableCap;
    require(available >= amount, IMitosisVault__ExceededCap(asset, amount, available));
  }

  function _assertAssetInitialized(address asset) internal view override(MitosisVaultMatrix, MitosisVaultEOL) {
    require(_isAssetInitialized(_getStorageV1(), asset), IMitosisVault__AssetNotInitialized(asset));
  }

  function _assertAssetNotInitialized(StorageV1 storage $, address asset) internal view {
    require(!_isAssetInitialized($, asset), IMitosisVault__AssetAlreadyInitialized(asset));
  }

  function _assertNotHalted(StorageV1 storage $, address asset, AssetAction action) internal view {
    require(!_isHalted($, asset, action), StdError.Halted());
  }

  function _isHalted(StorageV1 storage $, address asset, AssetAction action) internal view returns (bool) {
    return $.assets[asset].isHalted[action];
  }

  function _isAssetInitialized(StorageV1 storage $, address asset) internal view returns (bool) {
    return $.assets[asset].initialized;
  }

  function _setCap(StorageV1 storage $, address asset, uint256 newCap) internal {
    AssetInfo storage assetInfo = $.assets[asset];
    uint256 prevCap = assetInfo.maxCap;
    assetInfo.maxCap = newCap;
    assetInfo.availableCap = newCap;
    emit CapSet(_msgSender(), asset, prevCap, newCap);
  }

  function _haltAsset(StorageV1 storage $, address asset, AssetAction action) internal {
    $.assets[asset].isHalted[action] = true;
    emit AssetHalted(asset, action);
  }

  function _resumeAsset(StorageV1 storage $, address asset, AssetAction action) internal {
    $.assets[asset].isHalted[action] = false;
    emit AssetResumed(asset, action);
  }

  function _deposit(address asset, address to, uint256 amount) internal override(MitosisVaultMatrix, MitosisVaultEOL) {
    StorageV1 storage $ = _getStorageV1();
    require(to != address(0), StdError.ZeroAddress('to'));
    require(amount != 0, StdError.ZeroAmount());

    _assertAssetInitialized(asset);
    _assertNotHalted($, asset, AssetAction.Deposit);
    _assertCapNotExceeded($, asset, amount);

    $.assets[asset].availableCap -= amount;
    IERC20(asset).safeTransferFrom(_msgSender(), address(this), amount);
  }
}
