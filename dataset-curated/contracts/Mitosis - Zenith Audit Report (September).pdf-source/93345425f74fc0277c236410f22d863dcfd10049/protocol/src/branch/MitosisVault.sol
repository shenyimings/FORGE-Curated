// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Address } from '@oz/utils/Address.sol';
import { Math } from '@oz/utils/math/Math.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { AssetAction, IMitosisVault } from '../interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../interfaces/branch/IMitosisVaultEntrypoint.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { Pausable } from '../lib/Pausable.sol';
import { StdError } from '../lib/StdError.sol';
import { Versioned } from '../lib/Versioned.sol';
import { MitosisVaultVLF } from './MitosisVaultVLF.sol';

contract MitosisVault is
  IMitosisVault,
  Pausable,
  AccessControlEnumerableUpgradeable,
  UUPSUpgradeable,
  MitosisVaultVLF,
  Versioned
{
  using SafeERC20 for IERC20;
  using ERC7201Utils for string;

  /// @dev Role for managing caps
  bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256('LIQUIDITY_MANAGER_ROLE');

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
    __AccessControl_init();
    __AccessControlEnumerable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, owner_);
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

  function entrypoint() external view override returns (address) {
    return address(_getStorageV1().entrypoint);
  }

  function quoteDeposit(address asset, address to, uint256 amount) external view returns (uint256) {
    return _getStorageV1().entrypoint.quoteDeposit(asset, to, amount);
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

  function deposit(address asset, address to, uint256 amount) external payable whenNotPaused {
    _deposit(asset, to, amount);

    _entrypoint().deposit{ value: msg.value }(asset, to, amount, _msgSender());

    emit Deposited(asset, to, amount);
  }

  function withdraw(address asset, address to, uint256 amount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);
    _assertAssetInitialized(asset);

    $.assets[asset].availableCap += amount;

    IERC20(asset).safeTransfer(to, amount);

    emit Withdrawn(asset, to, amount);
  }

  //=========== NOTE: MUTATIVE - ROLE BASED FUNCTIONS ===========//

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

  function _authorizePause(address) internal view override onlyRole(DEFAULT_ADMIN_ROLE) { }

  function setEntrypoint(address entrypoint_) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _getStorageV1().entrypoint = IMitosisVaultEntrypoint(entrypoint_);
    emit EntrypointSet(address(entrypoint_));
  }

  function setCap(address asset, uint256 newCap) external onlyRole(LIQUIDITY_MANAGER_ROLE) {
    StorageV1 storage $ = _getStorageV1();
    _assertAssetInitialized(asset);

    _setCap($, asset, newCap);
  }

  function haltAsset(address asset, AssetAction action) external onlyRole(DEFAULT_ADMIN_ROLE) {
    StorageV1 storage $ = _getStorageV1();
    _assertAssetInitialized(asset);
    return _haltAsset($, asset, action);
  }

  function resumeAsset(address asset, AssetAction action) external onlyRole(DEFAULT_ADMIN_ROLE) {
    StorageV1 storage $ = _getStorageV1();
    _assertAssetInitialized(asset);
    return _resumeAsset($, asset, action);
  }

  //=========== NOTE: INTERNAL FUNCTIONS ===========//

  function _entrypoint() internal view override returns (IMitosisVaultEntrypoint) {
    return IMitosisVaultEntrypoint(_getStorageV1().entrypoint);
  }

  function _assertOnlyEntrypoint(StorageV1 storage $) internal view {
    require(_msgSender() == address($.entrypoint), StdError.Unauthorized());
  }

  function _assertCapNotExceeded(StorageV1 storage $, address asset, uint256 amount) internal view {
    uint256 available = $.assets[asset].availableCap;
    require(available >= amount, IMitosisVault__ExceededCap(asset, amount, available));
  }

  function _assertAssetInitialized(address asset) internal view override {
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
    uint256 prevSpent = prevCap - assetInfo.availableCap;

    assetInfo.maxCap = newCap;
    assetInfo.availableCap = newCap - Math.min(prevSpent, newCap);

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

  function _deposit(address asset, address to, uint256 amount) internal override {
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
