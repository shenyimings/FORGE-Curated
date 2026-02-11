// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import { IStrategyExecutor } from '../../src/interfaces/branch/strategy/IStrategyExecutor.sol';

contract MockStrategyExecutor is IStrategyExecutor {
  function execute(address target, bytes calldata data, uint256 value) external returns (bytes memory result) { }

  function execute(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
    external
    returns (bytes[] memory result)
  { }
}
