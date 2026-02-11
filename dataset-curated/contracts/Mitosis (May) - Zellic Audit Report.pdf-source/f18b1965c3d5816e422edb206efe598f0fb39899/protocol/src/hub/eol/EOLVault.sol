// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC4626 } from '@solady/tokens/ERC4626.sol';

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { ReentrancyGuardTransient } from '@oz/utils/ReentrancyGuardTransient.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { Pausable } from '../../lib/Pausable.sol';

contract EOLVault is ERC4626, Ownable2StepUpgradeable, Pausable, ReentrancyGuardTransient {
  using ERC7201Utils for string;

  struct StorageV1 {
    address asset;
    string name;
    string symbol;
    uint8 decimals;
  }

  string private constant _NAMESPACE = 'mitosis.storage.EOLVault.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, IERC20Metadata asset_, string memory name_, string memory symbol_)
    external
    initializer
  {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __Pausable_init();

    if (bytes(name_).length == 0 || bytes(symbol_).length == 0) {
      name_ = string.concat('Mitosis EOL ', asset_.name());
      symbol_ = string.concat('mi', asset_.symbol());
    }

    StorageV1 storage $ = _getStorageV1();
    $.asset = address(asset_);
    $.name = name_;
    $.symbol = symbol_;

    (bool success, uint8 result) = _tryGetAssetDecimals(address(asset_));
    $.decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
  }

  function asset() public view override returns (address) {
    return _getStorageV1().asset;
  }

  function name() public view override returns (string memory) {
    return _getStorageV1().name;
  }

  function symbol() public view override returns (string memory) {
    return _getStorageV1().symbol;
  }

  function _underlyingDecimals() internal view override returns (uint8) {
    return _getStorageV1().decimals;
  }

  function deposit(uint256 assets, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
    return super.deposit(assets, receiver);
  }

  function mint(uint256 shares, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
    return super.mint(shares, receiver);
  }

  /// @dev There's no redeem period for EOL vaults for initial phase
  function withdraw(uint256 assets, address receiver, address owner)
    public
    override
    nonReentrant
    whenNotPaused
    returns (uint256)
  {
    return super.withdraw(assets, receiver, owner);
  }

  /// @dev There's no redeem period for EOL vaults for initial phase
  function redeem(uint256 shares, address receiver, address owner)
    public
    override
    nonReentrant
    whenNotPaused
    returns (uint256)
  {
    return super.redeem(shares, receiver, owner);
  }

  function _authorizePause(address) internal view override onlyOwner { }
}
