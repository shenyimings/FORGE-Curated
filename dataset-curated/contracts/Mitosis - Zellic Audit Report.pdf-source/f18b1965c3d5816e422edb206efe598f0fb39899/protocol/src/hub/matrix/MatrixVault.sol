// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { Math } from '@oz/utils/math/Math.sol';
import { ReentrancyGuardTransient } from '@oz/utils/ReentrancyGuardTransient.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';

import { ERC4626 } from '@solady/tokens/ERC4626.sol';

import { IMatrixVault } from '../../interfaces/hub/matrix/IMatrixVault.sol';
import { Pausable } from '../../lib/Pausable.sol';
import { StdError } from '../../lib/StdError.sol';
import { MatrixVaultStorageV1 } from './MatrixVaultStorageV1.sol';

/**
 * @title MatrixVault
 * @notice Base implementation of an MatrixVault
 */
abstract contract MatrixVault is
  MatrixVaultStorageV1,
  ERC4626,
  Ownable2StepUpgradeable,
  Pausable,
  ReentrancyGuardTransient
{
  using Math for uint256;

  function __MatrixVault_init(
    address owner_,
    address assetManager_,
    IERC20Metadata asset_,
    string memory name_,
    string memory symbol_
  ) internal {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __Pausable_init();

    if (bytes(name_).length == 0 || bytes(symbol_).length == 0) {
      name_ = string.concat('Mitosis Matrix ', asset_.name());
      symbol_ = string.concat('ma', asset_.symbol());
    }

    StorageV1 storage $ = _getStorageV1();
    $.asset = address(asset_);
    $.name = name_;
    $.symbol = symbol_;

    (bool success, uint8 result) = _tryGetAssetDecimals(address(asset_));
    $.decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;

    _setAssetManager($, assetManager_);
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

  // Mutative functions

  function deposit(uint256 assets, address receiver)
    public
    virtual
    override
    nonReentrant
    whenNotPaused
    returns (uint256)
  {
    uint256 maxAssets = maxDeposit(receiver);
    require(assets <= maxAssets, DepositMoreThanMax());

    uint256 shares = previewDeposit(assets);
    _deposit(_msgSender(), receiver, assets, shares);

    return shares;
  }

  function mint(uint256 shares, address receiver) public virtual override nonReentrant whenNotPaused returns (uint256) {
    uint256 maxShares = maxMint(receiver);
    require(shares <= maxShares, MintMoreThanMax());

    uint256 assets = previewMint(shares);
    _deposit(_msgSender(), receiver, assets, shares);

    return assets;
  }

  function withdraw(uint256 assets, address receiver, address owner)
    public
    override
    nonReentrant
    whenNotPaused
    returns (uint256)
  {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyReclaimQueue($);

    uint256 maxAssets = maxWithdraw(owner);
    require(assets <= maxAssets, WithdrawMoreThanMax());

    uint256 shares = previewWithdraw(assets);
    _withdraw(_msgSender(), receiver, owner, assets, shares);

    return shares;
  }

  function redeem(uint256 shares, address receiver, address owner)
    public
    override
    nonReentrant
    whenNotPaused
    returns (uint256)
  {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyReclaimQueue($);

    uint256 maxShares = maxRedeem(owner);
    require(shares <= maxShares, RedeemMoreThanMax());

    uint256 assets = previewRedeem(shares);
    _withdraw(_msgSender(), receiver, owner, assets, shares);

    return assets;
  }

  // general overrides

  function _authorizePause(address) internal view override onlyOwner { }
}
