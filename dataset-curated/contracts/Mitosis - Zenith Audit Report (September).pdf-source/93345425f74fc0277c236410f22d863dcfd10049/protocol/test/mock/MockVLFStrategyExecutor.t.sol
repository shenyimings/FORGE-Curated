// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';

import { IMitosisVault } from '../../src/interfaces/branch/IMitosisVault.sol';
import { IVLFStrategyExecutor } from '../../src/interfaces/branch/strategy/IVLFStrategyExecutor.sol';
import { ITally } from '../../src/interfaces/branch/strategy/tally/ITally.sol';

contract MockVLFStrategyExecutor is IVLFStrategyExecutor {
  IMitosisVault _vault;
  IERC20 _asset;
  address _hubVLFVault;

  constructor(IMitosisVault vault_, IERC20 asset_, address hubVLFVault_) {
    _vault = vault_;
    _asset = asset_;
    _hubVLFVault = hubVLFVault_;
  }

  function vault() external view returns (IMitosisVault) {
    return _vault;
  }

  function asset() external view returns (IERC20) {
    return _asset;
  }

  function hubVLFVault() external view returns (address) {
    return _hubVLFVault;
  }

  function strategist() external view returns (address) { }

  function executor() external view returns (address) { }

  function emergencyManager() external view returns (address) { }

  function tally() external view returns (ITally) { }

  function totalBalance() external view returns (uint256) {
    return _asset.balanceOf(address(this));
  }

  function storedTotalBalance() external view returns (uint256) { }

  function quoteDeallocateLiquidity(uint256 amount) external view returns (uint256) { }

  function quoteSettleYield(uint256 amount) external view returns (uint256) { }

  function quoteSettleLoss(uint256 amount) external view returns (uint256) { }

  function quoteSettleExtraRewards(address reward, uint256 amount) external view returns (uint256) { }

  function deallocateLiquidity(uint256 amount) external payable { }

  function fetchLiquidity(uint256 amount) external { }

  function returnLiquidity(uint256 amount) external {
    _asset.approve(address(_vault), amount);
    _vault.returnVLF(_hubVLFVault, amount);
  }

  function settle() external payable { }

  function settleExtraRewards(address reward, uint256 amount) external payable { }

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
