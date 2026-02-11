// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from '@oz/access/Ownable.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { Math } from '@oz/utils/math/Math.sol';

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { StdError } from '../../lib/StdError.sol';
import { MatrixVault } from './MatrixVault.sol';

/**
 * @title MatrixVaultCapped
 * @notice Adds a cap to the MatrixVault's deposit / mint function
 */
contract MatrixVaultCapped is MatrixVault {
  using ERC7201Utils for string;

  /// @custom:storage-location mitosis.storage.MatrixVaultCapped
  struct MatrixVaultCappedStorage {
    uint256 cap;
  }

  event CapSet(address indexed setter, uint256 prevCap, uint256 newCap);

  // =========================== NOTE: STORAGE DEFINITIONS =========================== //

  string private constant _NAMESPACE = 'mitosis.storage.MatrixVaultCapped';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getMatrixVaultCappedStorage() private view returns (MatrixVaultCappedStorage storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // ============================ NOTE: INITIALIZATION FUNCTIONS ============================ //

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address owner_,
    address assetManager_,
    IERC20Metadata asset_,
    string memory name,
    string memory symbol
  ) external initializer {
    __MatrixVault_init(owner_, assetManager_, asset_, name, symbol);
  }

  // ============================ NOTE: VIEW FUNCTIONS ============================ //

  function loadCap() external view returns (uint256) {
    return _getMatrixVaultCappedStorage().cap;
  }

  function maxDeposit(address) public view override returns (uint256) {
    uint256 totalShares = totalSupply();
    uint256 cap = _getMatrixVaultCappedStorage().cap;

    if (totalShares >= cap) {
      return 0;
    }

    return convertToAssets(cap - totalShares);
  }

  function maxMint(address) public view override returns (uint256) {
    uint256 totalShares = totalSupply();
    uint256 cap = _getMatrixVaultCappedStorage().cap;

    if (totalShares >= cap) {
      return 0;
    }

    return cap - totalShares;
  }

  // ============================ NOTE: MUTATIVE FUNCTIONS ============================ //

  function setCap(uint256 newCap) external {
    StorageV1 storage $ = _getStorageV1();
    MatrixVaultCappedStorage storage capped = _getMatrixVaultCappedStorage();

    require(Ownable(address($.assetManager)).owner() == _msgSender(), StdError.Unauthorized());

    _setCap(capped, newCap);
  }

  // ============================ NOTE: INTERNAL FUNCTIONS ============================ //

  function _setCap(MatrixVaultCappedStorage storage $, uint256 newCap) internal {
    uint256 prevCap = $.cap;
    $.cap = newCap;
    emit CapSet(_msgSender(), prevCap, newCap);
  }
}
