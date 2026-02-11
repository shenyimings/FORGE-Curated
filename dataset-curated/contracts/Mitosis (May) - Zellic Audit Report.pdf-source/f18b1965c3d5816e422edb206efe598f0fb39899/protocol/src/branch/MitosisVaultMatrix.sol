// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';

import { IMitosisVaultEntrypoint } from '../interfaces/branch/IMitosisVaultEntrypoint.sol';
import { IMitosisVaultMatrix, MatrixAction } from '../interfaces/branch/IMitosisVaultMatrix.sol';
import { IMatrixStrategyExecutor } from '../interfaces/branch/strategy/IMatrixStrategyExecutor.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { Pausable } from '../lib/Pausable.sol';
import { StdError } from '../lib/StdError.sol';

abstract contract MitosisVaultMatrix is IMitosisVaultMatrix, Pausable, Ownable2StepUpgradeable {
  using ERC7201Utils for string;
  using SafeERC20 for IERC20;

  struct MatrixInfo {
    bool initialized;
    address asset;
    address strategyExecutor;
    uint256 availableLiquidity;
    mapping(MatrixAction => bool) isHalted;
  }

  struct MatrixStorageV1 {
    mapping(address hubMatrixVault => MatrixInfo) matrices;
  }

  string private constant _NAMESPACE = 'mitosis.storage.MitosisVault.Matrix.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getMatrixStorageV1() private view returns (MatrixStorageV1 storage $) {
    bytes32 slot = _slot;
    assembly {
      $.slot := slot
    }
  }

  //=========== NOTE: View ===========//

  function isMatrixActionHalted(address hubMatrixVault, MatrixAction action) external view returns (bool) {
    return _isMatrixHalted(_getMatrixStorageV1(), hubMatrixVault, action);
  }

  function isMatrixInitialized(address hubMatrixVault) external view returns (bool) {
    return _isMatrixInitialized(_getMatrixStorageV1(), hubMatrixVault);
  }

  function availableMatrix(address hubMatrixVault) external view returns (uint256) {
    return _getMatrixStorageV1().matrices[hubMatrixVault].availableLiquidity;
  }

  function matrixStrategyExecutor(address hubMatrixVault) external view returns (address) {
    return _getMatrixStorageV1().matrices[hubMatrixVault].strategyExecutor;
  }

  //=========== NOTE: Asset ===========//

  function _deposit(address asset, address to, uint256 amount) internal virtual;

  function _assertAssetInitialized(address asset) internal view virtual;

  function entrypoint() public view virtual returns (address);

  function depositWithSupplyMatrix(address asset, address to, address hubMatrixVault, uint256 amount)
    external
    whenNotPaused
  {
    _deposit(asset, to, amount);

    MatrixStorageV1 storage $ = _getMatrixStorageV1();
    _assertMatrixInitialized($, hubMatrixVault);
    require(asset == $.matrices[hubMatrixVault].asset, IMitosisVaultMatrix__InvalidMatrixVault(hubMatrixVault, asset));

    IMitosisVaultEntrypoint(entrypoint()).depositWithSupplyMatrix(asset, to, hubMatrixVault, amount);

    emit MatrixDepositedWithSupply(asset, to, hubMatrixVault, amount);
  }

  //=========== NOTE: Matrix Lifecycle ===========//

  function initializeMatrix(address hubMatrixVault, address asset) external whenNotPaused {
    require(entrypoint() == _msgSender(), StdError.Unauthorized());

    MatrixStorageV1 storage $ = _getMatrixStorageV1();

    _assertMatrixNotInitialized($, hubMatrixVault);
    _assertAssetInitialized(asset);

    $.matrices[hubMatrixVault].initialized = true;
    $.matrices[hubMatrixVault].asset = asset;

    emit MatrixInitialized(hubMatrixVault, asset);
  }

  function allocateMatrix(address hubMatrixVault, uint256 amount) external whenNotPaused {
    require(entrypoint() == _msgSender(), StdError.Unauthorized());

    MatrixStorageV1 storage $ = _getMatrixStorageV1();
    _assertMatrixInitialized($, hubMatrixVault);

    $.matrices[hubMatrixVault].availableLiquidity += amount;

    emit MatrixAllocated(hubMatrixVault, amount);
  }

  function deallocateMatrix(address hubMatrixVault, uint256 amount) external whenNotPaused {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();

    _assertMatrixInitialized($, hubMatrixVault);
    _assertOnlyStrategyExecutor($, hubMatrixVault);

    $.matrices[hubMatrixVault].availableLiquidity -= amount;
    IMitosisVaultEntrypoint(entrypoint()).deallocateMatrix(hubMatrixVault, amount);

    emit MatrixDeallocated(hubMatrixVault, amount);
  }

  function fetchMatrix(address hubMatrixVault, uint256 amount) external whenNotPaused {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();

    _assertMatrixInitialized($, hubMatrixVault);
    _assertOnlyStrategyExecutor($, hubMatrixVault);
    _assertNotHalted($, hubMatrixVault, MatrixAction.FetchMatrix);

    MatrixInfo storage matrixInfo = $.matrices[hubMatrixVault];

    matrixInfo.availableLiquidity -= amount;
    IERC20(matrixInfo.asset).safeTransfer(matrixInfo.strategyExecutor, amount);

    emit MatrixFetched(hubMatrixVault, amount);
  }

  function returnMatrix(address hubMatrixVault, uint256 amount) external whenNotPaused {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();

    _assertMatrixInitialized($, hubMatrixVault);
    _assertOnlyStrategyExecutor($, hubMatrixVault);

    MatrixInfo storage matrixInfo = $.matrices[hubMatrixVault];

    matrixInfo.availableLiquidity += amount;
    IERC20(matrixInfo.asset).safeTransferFrom(matrixInfo.strategyExecutor, address(this), amount);

    emit MatrixReturned(hubMatrixVault, amount);
  }

  function settleMatrixYield(address hubMatrixVault, uint256 amount) external whenNotPaused {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();

    _assertMatrixInitialized($, hubMatrixVault);
    _assertOnlyStrategyExecutor($, hubMatrixVault);

    IMitosisVaultEntrypoint(entrypoint()).settleMatrixYield(hubMatrixVault, amount);

    emit MatrixYieldSettled(hubMatrixVault, amount);
  }

  function settleMatrixLoss(address hubMatrixVault, uint256 amount) external whenNotPaused {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();

    _assertMatrixInitialized($, hubMatrixVault);
    _assertOnlyStrategyExecutor($, hubMatrixVault);

    IMitosisVaultEntrypoint(entrypoint()).settleMatrixLoss(hubMatrixVault, amount);

    emit MatrixLossSettled(hubMatrixVault, amount);
  }

  function settleMatrixExtraRewards(address hubMatrixVault, address reward, uint256 amount) external whenNotPaused {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();

    _assertMatrixInitialized($, hubMatrixVault);
    _assertOnlyStrategyExecutor($, hubMatrixVault);
    _assertAssetInitialized(reward);
    require(reward != $.matrices[hubMatrixVault].asset, StdError.InvalidAddress('reward'));

    IERC20(reward).safeTransferFrom(_msgSender(), address(this), amount);
    IMitosisVaultEntrypoint(entrypoint()).settleMatrixExtraRewards(hubMatrixVault, reward, amount);

    emit MatrixExtraRewardsSettled(hubMatrixVault, reward, amount);
  }

  //=========== NOTE: OWNABLE FUNCTIONS ===========//

  function haltMatrix(address hubMatrixVault, MatrixAction action) external onlyOwner {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();
    _assertMatrixInitialized($, hubMatrixVault);
    return _haltMatrix($, hubMatrixVault, action);
  }

  function resumeMatrix(address hubMatrixVault, MatrixAction action) external onlyOwner {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();
    _assertMatrixInitialized($, hubMatrixVault);
    return _resumeMatrix($, hubMatrixVault, action);
  }

  function setMatrixStrategyExecutor(address hubMatrixVault, address strategyExecutor_) external onlyOwner {
    MatrixStorageV1 storage $ = _getMatrixStorageV1();
    MatrixInfo storage matrixInfo = $.matrices[hubMatrixVault];

    _assertMatrixInitialized($, hubMatrixVault);

    if (matrixInfo.strategyExecutor != address(0)) {
      // NOTE: no way to check if every extra rewards are settled.
      bool drained = IMatrixStrategyExecutor(matrixInfo.strategyExecutor).totalBalance() == 0
        && IMatrixStrategyExecutor(matrixInfo.strategyExecutor).storedTotalBalance() == 0;
      require(drained, IMitosisVaultMatrix__StrategyExecutorNotDrained(hubMatrixVault, matrixInfo.strategyExecutor));
    }

    require(
      hubMatrixVault == IMatrixStrategyExecutor(strategyExecutor_).hubMatrixVault(),
      StdError.InvalidId('matrixStrategyExecutor.hubMatrixVault')
    );
    require(
      address(this) == address(IMatrixStrategyExecutor(strategyExecutor_).vault()),
      StdError.InvalidAddress('matrixStrategyExecutor.vault')
    );
    require(
      matrixInfo.asset == address(IMatrixStrategyExecutor(strategyExecutor_).asset()),
      StdError.InvalidAddress('matrixStrategyExecutor.asset')
    );

    matrixInfo.strategyExecutor = strategyExecutor_;
    emit MatrixStrategyExecutorSet(hubMatrixVault, strategyExecutor_);
  }

  //=========== NOTE: INTERNAL FUNCTIONS ===========//

  function _isMatrixHalted(MatrixStorageV1 storage $, address hubMatrixVault, MatrixAction action)
    internal
    view
    returns (bool)
  {
    return $.matrices[hubMatrixVault].isHalted[action];
  }

  function _haltMatrix(MatrixStorageV1 storage $, address hubMatrixVault, MatrixAction action) internal {
    $.matrices[hubMatrixVault].isHalted[action] = true;
    emit MatrixHalted(hubMatrixVault, action);
  }

  function _resumeMatrix(MatrixStorageV1 storage $, address hubMatrixVault, MatrixAction action) internal {
    $.matrices[hubMatrixVault].isHalted[action] = false;
    emit MatrixResumed(hubMatrixVault, action);
  }

  function _assertNotHalted(MatrixStorageV1 storage $, address hubMatrixVault, MatrixAction action) internal view {
    require(!_isMatrixHalted($, hubMatrixVault, action), StdError.Halted());
  }

  function _isMatrixInitialized(MatrixStorageV1 storage $, address hubMatrixVault) internal view returns (bool) {
    return $.matrices[hubMatrixVault].initialized;
  }

  function _assertMatrixInitialized(MatrixStorageV1 storage $, address hubMatrixVault) internal view {
    require(_isMatrixInitialized($, hubMatrixVault), IMitosisVaultMatrix__MatrixNotInitialized(hubMatrixVault));
  }

  function _assertMatrixNotInitialized(MatrixStorageV1 storage $, address hubMatrixVault) internal view {
    require(!_isMatrixInitialized($, hubMatrixVault), IMitosisVaultMatrix__MatrixAlreadyInitialized(hubMatrixVault));
  }

  function _assertOnlyStrategyExecutor(MatrixStorageV1 storage $, address hubMatrixVault) internal view {
    require(_msgSender() == $.matrices[hubMatrixVault].strategyExecutor, StdError.Unauthorized());
  }
}
