// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IMitosisVault } from '../../src/interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../../src/interfaces/branch/IMitosisVaultEntrypoint.sol';

contract MockMitosisVaultEntrypoint is IMitosisVaultEntrypoint {
  function vault() external view returns (IMitosisVault) { }

  function mitosisDomain() external view returns (uint32) { }

  function mitosisAddr() external view returns (bytes32) { }

  function deposit(address asset, address to, uint256 amount) external { }

  function depositWithSupplyMatrix(address asset, address to, address hubMatrixVault, uint256 amount) external { }

  function depositWithSupplyEOL(address asset, address to, address hubEOLVault, uint256 amount) external { }

  function deallocateMatrix(address hubMatrixVault, uint256 amount) external { }

  function settleMatrixYield(address hubMatrixVault, uint256 amount) external { }

  function settleMatrixLoss(address hubMatrixVault, uint256 amount) external { }

  function settleMatrixExtraRewards(address hubMatrixVault, address reward, uint256 amount) external { }
}
