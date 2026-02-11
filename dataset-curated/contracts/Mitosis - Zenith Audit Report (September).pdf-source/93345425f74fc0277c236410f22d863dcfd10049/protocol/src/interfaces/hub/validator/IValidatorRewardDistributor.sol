// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IGovMITO } from '../IGovMITO.sol';
import { IGovMITOEmission } from '../IGovMITOEmission.sol';
import { IEpochFeeder } from './IEpochFeeder.sol';
import { IValidatorContributionFeed } from './IValidatorContributionFeed.sol';
import { IValidatorManager } from './IValidatorManager.sol';
import { IValidatorStakingHub } from './IValidatorStakingHub.sol';

/// @title IValidatorRewardDistributor
/// @notice Interface for the ValidatorRewardDistributor contract that handles distribution of validator rewards.
interface IValidatorRewardDistributor {
  // Structs
  struct ClaimConfigResponse {
    uint8 version;
    uint32 maxClaimEpochs;
    uint32 maxStakerBatchSize;
    uint32 maxOperatorBatchSize;
  }

  // Events
  event StakerRewardsClaimed(
    address indexed staker,
    address indexed valAddr,
    address indexed recipient,
    uint256 amount,
    uint256 fromEpoch,
    uint256 toEpoch
  );
  event OperatorRewardsClaimed(
    address indexed valAddr, address indexed recipient, uint256 amount, uint256 fromEpoch, uint256 toEpoch
  );

  event StakerRewardClaimApprovalUpdated(address account, address valAddr, address claimer, bool approval);
  event OperatorRewardClaimApprovalUpdated(address account, address valAddr, address claimer, bool approval);
  event ClaimConfigUpdated(uint8 version, bytes encodedConfig);

  // Custom errors
  error IValidatorRewardDistributor__MaxStakerBatchSizeExceeded();
  error IValidatorRewardDistributor__MaxOperatorBatchSizeExceeded();
  error IValidatorRewardDistributor__ArrayLengthMismatch();

  // ========== VIEWS ========== //

  /// @notice Returns the epoch feeder contract.
  function epochFeeder() external view returns (IEpochFeeder);

  /// @notice Returns the validator registry contract.
  function validatorManager() external view returns (IValidatorManager);

  /// @notice Returns the validator contribution feed contract.
  function validatorContributionFeed() external view returns (IValidatorContributionFeed);

  /// @notice Returns the validator staking hub contract.
  function validatorStakingHub() external view returns (IValidatorStakingHub);

  /// @notice Returns the gov MITO emission contract.
  function govMITOEmission() external view returns (IGovMITOEmission);

  /// @notice Returns the claim config.
  function claimConfig() external view returns (ClaimConfigResponse memory);

  /// @notice Checks if the claimer can claim staker rewards for the validator on behalf of the account.
  function stakerClaimAllowed(address account, address valAddr, address claimer) external view returns (bool);

  /// @notice Checks if the claimer can claim operator rewards for the validator on behalf of the account.
  function operatorClaimAllowed(address account, address valAddr, address claimer) external view returns (bool);

  /// @notice Returns the last claimed staker rewards epoch for a validator.
  /// @param staker The staker address to check rewards for.
  /// @param valAddr The validator address to check rewards for.
  /// @return epoch The last claimed staker rewards epoch.
  function lastClaimedStakerRewardsEpoch(address staker, address valAddr) external view returns (uint256);

  /// @notice Returns the last claimed operator rewards epoch for a validator.
  /// @param valAddr The validator address to check rewards for.
  /// @return epoch The last claimed operator rewards epoch.
  function lastClaimedOperatorRewardsEpoch(address valAddr) external view returns (uint256);

  /// @notice Returns the total claimable rewards for multiple validators and a staker.
  /// @param staker The staker address to check rewards for.
  /// @param valAddr The validator address to check rewards for.
  /// @return amount The total amount of rewards that can be claimed.
  /// @return nextEpoch The next epoch to claim rewards from.
  function claimableStakerRewards(address staker, address valAddr) external view returns (uint256, uint256);

  /// @notice Returns the total claimable operator rewards for a validator.
  /// @param valAddr The validator address to check rewards for.
  /// @return amount The total amount of rewards that can be claimed.
  /// @return nextEpoch The next epoch to claim rewards from.
  function claimableOperatorRewards(address valAddr) external view returns (uint256, uint256);

  /// @notice Sets the approval status for an operator to claim rewards on behalf of msg.sender.
  /// @param valAddr The address of the target validator.
  /// @param claimer The address to be approved.
  /// @param approval A boolean indicating whether the claim is approved or not.
  function setStakerClaimApprovalStatus(address valAddr, address claimer, bool approval) external;

  /// @notice Sets the approval status for an operator to claim rewards.
  /// @param valAddr The address of the target validator.
  /// @param claimer The address to be approved.
  /// @param approval A boolean indicating whether the claim is approved or not.
  function setOperatorClaimApprovalStatus(address valAddr, address claimer, bool approval) external;

  /// @notice Claims rewards for multiple validators over a range of epochs.
  /// @param staker The staker address to claim rewards for.
  /// @param valAddr The validator address to claim rewards for.
  /// @return amount The total amount of rewards that were claimed.
  function claimStakerRewards(address staker, address valAddr) external returns (uint256);

  /// @notice Claims rewards for multiple validators over a range of epochs.
  /// @param stakers The staker addresses to claim rewards for.
  /// @param valAddrs The validator addresses to claim rewards for.
  /// @return amount The total amount of rewards that were claimed.
  function batchClaimStakerRewards(address[] calldata stakers, address[][] calldata valAddrs)
    external
    returns (uint256);

  /// @notice Claims operator rewards for a validator.
  /// @param valAddr The validator address to claim rewards for.
  /// @return amount The total amount of rewards that were claimed.
  function claimOperatorRewards(address valAddr) external returns (uint256);

  /// @notice Claims operator rewards for multiple validators.
  /// @param valAddrs The validator addresses to claim rewards for.
  /// @return amount The total amount of rewards that were claimed.
  function batchClaimOperatorRewards(address[] calldata valAddrs) external returns (uint256);

  /// @notice Sets the claim config.
  /// @param maxClaimEpochs The maximum number of epochs that can be claimed at once.
  /// @param maxStakerBatchSize The maximum number of stakers that can be processed in a batch operation.
  /// @param maxOperatorBatchSize The maximum number of operators that can be processed in a batch operation.
  function setClaimConfig(uint32 maxClaimEpochs, uint32 maxStakerBatchSize, uint32 maxOperatorBatchSize) external;
}
