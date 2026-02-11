// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import { IStrategyExecutor } from '../../src/interfaces/branch/strategy/IStrategyExecutor.sol';
import { IManagerWithMerkleVerification } from
  '../../src/interfaces/branch/strategy/manager/IManagerWithMerkleVerification.sol';

contract MockManagerWithMerkleVerification is IManagerWithMerkleVerification {
  function manageRoot(address, address strategist) external view returns (bytes32) { }

  function setManageRoot(address, address strategist, bytes32 _manageRoot) external { }

  function manage(
    address strategyExecutor,
    bytes32[][] calldata,
    address[] calldata,
    address[] calldata targets,
    bytes[] calldata targetData,
    uint256[] calldata values
  ) external {
    for (uint256 i = 0; i < targets.length; i++) {
      IStrategyExecutor(strategyExecutor).execute(targets[i], targetData[i], values[i]);
    }
  }
}
