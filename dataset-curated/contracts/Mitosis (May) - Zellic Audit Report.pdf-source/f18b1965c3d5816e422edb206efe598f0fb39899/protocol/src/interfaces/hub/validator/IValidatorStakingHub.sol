// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IConsensusValidatorEntrypoint } from '../consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IValidatorManager } from './IValidatorManager.sol';

/// @title IValidatorStakingHub
/// @notice Interface for the ValidatorStakingHub contract.
/// @dev This interface defines the actions that notifiers can perform to track staking.
interface IValidatorStakingHub {
  // ========== EVENTS ========== //

  /**
   * @notice Emitted when a new notifier is added.
   * @param notifier The address of the notifier that registered.
   */
  event NotifierAdded(address indexed notifier);

  /**
   * @notice Emitted when a notifier is removed.
   * @param notifier The address of the notifier that unregistered.
   */
  event NotifierRemoved(address indexed notifier);

  /**
   * @notice Emitted when a stake is notified.
   * @param valAddr Validator address to be notified.
   * @param staker Staker address to be notified.
   * @param amount Amount of stake to be notified.
   * @param notifier The address of the notifier that notified the stake.
   */
  event NotifiedStake(address indexed valAddr, address indexed staker, uint256 amount, address notifier);

  /**
   * @notice Emitted when an unstake is notified.
   * @param valAddr Validator address to be notified.
   * @param staker Staker address to be notified.
   * @param amount Amount of unstake to be notified.
   * @param notifier The address of the notifier that notified the unstake.
   */
  event NotifiedUnstake(address indexed valAddr, address indexed staker, uint256 amount, address notifier);

  /**
   * @notice Emitted when a redelegation is notified.
   * @param fromVal Validator address to be notified.
   * @param toVal Validator address to be notified.
   * @param staker Staker address to be notified.
   * @param amount Amount of redelegation to be notified.
   * @param notifier The address of the notifier that notified the redelegation.
   */
  event NotifiedRedelegation(
    address indexed fromVal, address indexed toVal, address indexed staker, uint256 amount, address notifier
  );

  // ========== ERRORS ========== //

  error IValidatorStakingHub__InvalidNotifier(address notifier);
  error IValidatorStakingHub__NotifierAlreadyRegistered(address notifier);
  error IValidatorStakingHub__NotifierNotRegistered(address notifier);
  error IValidatorStakingHub__RedelegatedFromSelf(address valAddr);

  // ========== VIEWS ========== //

  /**
   * @notice Returns the entrypoint of the hub.
   * @return entrypoint The entrypoint of the hub.
   */
  function entrypoint() external view returns (IConsensusValidatorEntrypoint);

  /**
   * @notice Returns whether the notifier is registered.
   * @param notifier The address of the notifier.
   * @return isNotifier Whether the notifier is registered.
   */
  function isNotifier(address notifier) external view returns (bool);

  /**
   * @notice Returns the total amount of stake for a validator.
   * @param valAddr The address of the validator.
   * @param timestamp The timestamp to get the total staked amount for.
   * @return total The total amount of stake for the validator.
   */
  function validatorTotal(address valAddr, uint48 timestamp) external view returns (uint256);

  /**
   * @notice Returns the total amount twab of stake for a validator.
   * @param valAddr The address of the validator.
   * @param timestamp The timestamp to get the twab of total staked amount for.
   * @return totalTWAB The total amount twab of stake for the validator.
   */
  function validatorTotalTWAB(address valAddr, uint48 timestamp) external view returns (uint256);

  /**
   * @notice Returns the total amount of stake for a staker.
   * @param staker The address of the staker.
   * @param timestamp The timestamp to get the total staked amount for.
   * @return total The total amount of stake for the staker.
   */
  function stakerTotal(address staker, uint48 timestamp) external view returns (uint256);

  /**
   * @notice Returns the total amount twab of stake for a staker.
   * @param staker The address of the staker.
   * @param timestamp The timestamp to get the twab of total staked amount for.
   * @return totalTWAB The total amount twab of stake for the staker.
   */
  function stakerTotalTWAB(address staker, uint48 timestamp) external view returns (uint256);

  /**
   * @notice Returns the total amount of stake for a validator and a staker.
   * @param valAddr The address of the validator.
   * @param staker The address of the staker.
   * @param timestamp The timestamp to get the total staked amount for.
   * @return total The total amount of stake for the validator and staker.
   */
  function validatorStakerTotal(address valAddr, address staker, uint48 timestamp) external view returns (uint256);

  /**
   * @notice Returns the total amount twab of stake for a validator and a staker.
   * @param valAddr The address of the validator.
   * @param staker The address of the staker.
   * @param timestamp The timestamp to get the twab of total staked amount for.
   * @return totalTWAB The total amount twab of stake for the validator and staker.
   */
  function validatorStakerTotalTWAB(address valAddr, address staker, uint48 timestamp) external view returns (uint256);

  // ========== ADMIN ACTIONS ========== //

  /**
   * @notice Adds a new notifier to the hub.
   * @param notifier The address of the notifier to add.
   */
  function addNotifier(address notifier) external;

  /**
   * @notice Removes a notifier from the hub.
   * @param notifier The address of the notifier to remove.
   */
  function removeNotifier(address notifier) external;

  // ========== NOTIFIER ACTIONS ========== //

  /**
   * @notice Notifies a stake.
   * @param valAddr Validator address to be notified.
   * @param staker Staker address to be notified.
   * @param amount Amount of stake to be notified.
   */
  function notifyStake(address valAddr, address staker, uint256 amount) external;

  /**
   * @notice Notifies an unstake.
   * @param valAddr Validator address to be notified.
   * @param staker Staker address to be notified.
   * @param amount Amount of unstake to be notified.
   */
  function notifyUnstake(address valAddr, address staker, uint256 amount) external;

  /**
   * @notice Notifies a redelegation.
   * @param fromValAddr Validator address to be notified.
   * @param toValAddr Validator address to be notified.
   * @param staker Staker address to be notified.
   * @param amount Amount of redelegation to be notified.
   */
  function notifyRedelegation(address fromValAddr, address toValAddr, address staker, uint256 amount) external;
}
