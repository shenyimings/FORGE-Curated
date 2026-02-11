// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Address } from '@oz/utils/Address.sol';

import { IMitosisVault } from '../../src/interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../../src/interfaces/branch/IMitosisVaultEntrypoint.sol';

contract MockMitosisVaultEntrypoint is IMitosisVaultEntrypoint {
  using Address for address payable;

  mapping(bytes4 => uint256) public gas;

  function setGas(bytes4 selector, uint256 gas_) external {
    gas[selector] = gas_;
  }

  function vault() external view returns (IMitosisVault) { }
  function mitosisDomain() external view returns (uint32) { }
  function mitosisAddr() external view returns (bytes32) { }

  // forgefmt: disable-start
  function quoteDeposit(address, address, uint256) external view returns (uint256)                       { return _quote(); }
  function quoteDepositWithSupplyVLF(address, address, address, uint256) external view returns (uint256) { return _quote(); }
  function quoteDeallocateVLF(address, uint256) external view returns (uint256)                          { return _quote(); }
  function quoteSettleVLFYield(address, uint256) external view returns (uint256)                         { return _quote(); }
  function quoteSettleVLFLoss(address, uint256) external view returns (uint256)                          { return _quote(); }
  function quoteSettleVLFExtraRewards(address, address, uint256) external view returns (uint256)         { return _quote(); }

  function deposit(address, address, uint256, address refund) external payable                       { _exec(refund); }
  function depositWithSupplyVLF(address, address, address, uint256, address refund) external payable { _exec(refund); }
  function deallocateVLF(address, uint256, address refund) external payable                          { _exec(refund); }
  function settleVLFYield(address, uint256, address refund) external payable                         { _exec(refund); }
  function settleVLFLoss(address, uint256, address refund) external payable                          { _exec(refund); }
  function settleVLFExtraRewards(address, address, uint256, address refund) external payable         { _exec(refund); }
  // forgefmt: disable-end

  function _quote() internal view returns (uint256) {
    return gas[msg.sig];
  }

  function _exec(address refund) internal {
    if (msg.value > gas[msg.sig]) payable(refund).sendValue(msg.value - gas[msg.sig]);
  }
}
