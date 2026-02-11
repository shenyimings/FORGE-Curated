// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { StdTally } from './StdTally.sol';

interface IManager {
  function asset() external view returns (address);
  function deposit(uint256 amount) external;
  function withdraw(uint256 amount, address receiver) external;
  function totalBalance() external view returns (uint256);
}

contract ManagerTally is StdTally {
  IManager public immutable manager;

  constructor(IManager manager_) {
    manager = manager_;
  }

  function _totalBalance(bytes memory) internal view override returns (uint256) {
    return manager.totalBalance();
  }
}
