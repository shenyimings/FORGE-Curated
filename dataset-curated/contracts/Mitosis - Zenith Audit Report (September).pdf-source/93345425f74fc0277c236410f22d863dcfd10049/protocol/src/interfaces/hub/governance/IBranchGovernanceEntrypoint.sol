// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface IBranchGovernanceEntrypoint {
  event ExecutionDispatched(
    uint256 indexed chainId, address[] targets, uint256[] values, bytes[] data, bytes32 predecessor, bytes32 salt
  );

  function quoteGovernanceExecution(
    uint256 chainId,
    address[] calldata targets,
    bytes[] calldata data,
    uint256[] calldata values,
    bytes32 predecessor,
    bytes32 salt
  ) external view returns (uint256);

  function dispatchGovernanceExecution(
    uint256 chainId,
    address[] calldata targets,
    bytes[] calldata data,
    uint256[] calldata values,
    bytes32 predecessor,
    bytes32 salt
  ) external payable;
}
