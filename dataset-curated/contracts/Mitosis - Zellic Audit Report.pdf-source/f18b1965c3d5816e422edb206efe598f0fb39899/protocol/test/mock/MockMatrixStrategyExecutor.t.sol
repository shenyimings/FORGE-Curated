// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';

import { IMitosisVault } from '../../src/interfaces/branch/IMitosisVault.sol';
import { IMatrixStrategyExecutor } from '../../src/interfaces/branch/strategy/IMatrixStrategyExecutor.sol';
import { ITally } from '../../src/interfaces/branch/strategy/tally/ITally.sol';

contract MockMatrixStrategyExecutor is IMatrixStrategyExecutor {
  IMitosisVault _vault;
  IERC20 _asset;
  address _hubMatrixVault;

  constructor(IMitosisVault vault_, IERC20 asset_, address hubMatrixVault_) {
    _vault = vault_;
    _asset = asset_;
    _hubMatrixVault = hubMatrixVault_;
  }

  function vault() external view returns (IMitosisVault) {
    return _vault;
  }

  function asset() external view returns (IERC20) {
    return _asset;
  }

  function hubMatrixVault() external view returns (address) {
    return _hubMatrixVault;
  }

  function strategist() external view returns (address) { }

  function executor() external view returns (address) { }

  function emergencyManager() external view returns (address) { }

  function tally() external view returns (ITally) { }

  function totalBalance() external view returns (uint256) {
    return _asset.balanceOf(address(this));
  }

  function storedTotalBalance() external view returns (uint256) { }

  function deallocateLiquidity(uint256 amount) external { }

  function fetchLiquidity(uint256 amount) external { }

  function returnLiquidity(uint256 amount) external {
    _asset.approve(address(_vault), amount);
    _vault.returnMatrix(_hubMatrixVault, amount);
  }

  function settle() external { }

  function settleExtraRewards(address reward, uint256 amount) external { }

  function execute(address target, bytes calldata data, uint256 value) external returns (bytes memory result) { }

  function execute(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
    external
    returns (bytes[] memory result)
  { }

  function setTally(address implementation) external { }

  function setEmergencyManager(address emergencyManager_) external { }

  function setStrategist(address strategist_) external { }

  function setExecutor(address executor_) external { }

  function unsetStrategist() external { }

  function unsetExecutor() external { }

  function pause() external { }

  function unpause() external { }
}
