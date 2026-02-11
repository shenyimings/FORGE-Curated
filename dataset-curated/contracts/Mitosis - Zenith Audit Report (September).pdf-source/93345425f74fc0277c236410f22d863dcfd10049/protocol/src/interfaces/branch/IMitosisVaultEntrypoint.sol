// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IMitosisVault } from './IMitosisVault.sol';

interface IMitosisVaultEntrypoint {
  function vault() external view returns (IMitosisVault);

  function mitosisDomain() external view returns (uint32);

  function mitosisAddr() external view returns (bytes32);

  //=========== NOTE: QUOTE FUNCTIONS ===========//

  function quoteDeposit(address asset, address to, uint256 amount) external view returns (uint256);

  function quoteDepositWithSupplyVLF(address asset, address to, address hubVLFVault, uint256 amount)
    external
    view
    returns (uint256);

  function quoteDeallocateVLF(address hubVLFVault, uint256 amount) external view returns (uint256);

  function quoteSettleVLFYield(address hubVLFVault, uint256 amount) external view returns (uint256);

  function quoteSettleVLFLoss(address hubVLFVault, uint256 amount) external view returns (uint256);

  function quoteSettleVLFExtraRewards(address hubVLFVault, address reward, uint256 amount)
    external
    view
    returns (uint256);

  //=========== NOTE: MUTATIVE FUNCTIONS ===========//

  function deposit(address asset, address to, uint256 amount, address refundTo) external payable;

  function depositWithSupplyVLF(address asset, address to, address hubVLFVault, uint256 amount, address refundTo)
    external
    payable;

  function deallocateVLF(address hubVLFVault, uint256 amount, address refundTo) external payable;

  function settleVLFYield(address hubVLFVault, uint256 amount, address refundTo) external payable;

  function settleVLFLoss(address hubVLFVault, uint256 amount, address refundTo) external payable;

  function settleVLFExtraRewards(address hubVLFVault, address reward, uint256 amount, address refundTo)
    external
    payable;
}
