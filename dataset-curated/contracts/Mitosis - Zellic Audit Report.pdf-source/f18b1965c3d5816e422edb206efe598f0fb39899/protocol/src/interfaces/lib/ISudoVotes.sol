// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IVotes } from '@oz/governance/utils/IVotes.sol';

interface ISudoVotes is IVotes {
  /**
   * @notice Emitted when the delegation manager is set.
   * @param previous The address of the previous delegation manager.
   * @param next The address of the new delegation manager.
   */
  event DelegationManagerSet(address indexed previous, address indexed next);

  /**
   * @notice Returns the address of the delegation manager.
   * @return delegationManager The address of the delegation manager.
   */
  function delegationManager() external view returns (address);

  /**
   * @notice Delegate votes from the sender to a delegatee.
   * @param account The address of the account to delegate votes from.
   * @param delegatee The address of the delegatee to delegate votes to.
   */
  function sudoDelegate(address account, address delegatee) external;

  /**
   * @notice Set the address of the delegation manager.
   * @param delegationManager_ The address of the new delegation manager.
   */
  function setDelegationManager(address delegationManager_) external;
}
