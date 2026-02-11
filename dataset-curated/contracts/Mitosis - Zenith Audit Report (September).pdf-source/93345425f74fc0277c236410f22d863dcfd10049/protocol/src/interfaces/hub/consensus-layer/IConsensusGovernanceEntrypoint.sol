// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface IConsensusGovernanceEntrypoint {
  event PermittedCallerSet(address caller, bool isPermitted);

  event MsgExecute(string[] messages);

  /**
   * @notice Execute messages in the consensus layer.
   * @dev The entire execution reverts if any message fails to execute in the consensus layer.
   * @param messages The messages to execute. Each message is a json string serialized from a protobuf message. Example of message is `{"@type": "/cosmos.upgrade.v1beta1.MsgSoftwareUpgrade", "authority": "...", "plan": {...}}`
   */
  function execute(string[] calldata messages) external;
}
