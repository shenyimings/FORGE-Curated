// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IGovMITO } from './IGovMITO.sol';
import { IEpochFeeder } from './validator/IEpochFeeder.sol';

interface IGovMITOEmission {
  struct ValidatorRewardConfig {
    uint256 rps;
    uint160 rateMultiplier; // 10000 = 100%
    uint48 renewalPeriod;
    uint48 startsFrom;
    address recipient;
  }

  struct ConfigureValidatorRewardEmissionRequest {
    uint256 rps;
    uint160 rateMultiplier;
    uint48 renewalPeriod;
  }

  error NotEnoughBalance();
  error NotEnoughReserve();

  event ValidatorRewardRequested(uint256 indexed epoch, address indexed recipient, uint256 amount);
  event ValidatorRewardEmissionAdded(address indexed sender, uint256 amount);
  event ValidatorRewardEmissionConfigured(uint256 rps, uint160 deductionRate, uint48 deductionPeriod, uint48 timestamp);
  event ValidatorRewardRecipientSet(address previousRecipient, address newRecipient);

  /**
   * @notice Returns the GovMITO token contract
   */
  function govMITO() external view returns (IGovMITO);

  /**
   * @notice Returns the epoch feeder contract
   */
  function epochFeeder() external view returns (IEpochFeeder);

  /**
   * @notice Returns the validator reward for a given epoch
   * @param epoch Epoch number
   * @return amount The total amount of gMITO tokens reserved for the validator reward
   */
  function validatorReward(uint256 epoch) external view returns (uint256 amount);

  /**
   * @notice Returns the total amount of gMITO tokens reserved for validator rewards
   */
  function validatorRewardTotal() external view returns (uint256);

  /**
   * @notice Returns the total amount of gMITO tokens spent on validator rewards
   */
  function validatorRewardSpent() external view returns (uint256);

  /**
   * @notice Returns the number of validator reward emissions
   */
  function validatorRewardEmissionsCount() external view returns (uint256);

  /**
   * @notice Returns the validator reward emission at the given index
   * @param index Index of the emission
   */
  function validatorRewardEmissionsByIndex(uint256 index)
    external
    view
    returns (uint256 rps, uint160 rateMultiplier, uint48 renewalPeriod);

  /**
   * @notice Returns the validator reward emission at the given timestamp
   * @param timestamp Timestamp to look up
   */
  function validatorRewardEmissionsByTime(uint48 timestamp)
    external
    view
    returns (uint256 rps, uint160 rateMultiplier, uint48 renewalPeriod);

  /**
   * @notice Returns the validator reward recipient
   */
  function validatorRewardRecipient() external view returns (address);

  /**
   * @notice Requests a validator reward
   * @param epoch Epoch number
   * @param recipient Address of the recipient
   * @param amount Amount of gMITO tokens to request
   * @return amount The amount of gMITO tokens transferred to the recipient
   */
  function requestValidatorReward(uint256 epoch, address recipient, uint256 amount) external returns (uint256);

  /**
   * @notice Adds a validator reward emission
   */
  function addValidatorRewardEmission() external payable;

  /**
   * @notice Configures the validator reward emission
   * @param rps The rate of gMITO tokens to emit per second
   * @param rateMultiplier The rate of gMITO tokens to deduct per second
   * @param renewalPeriod The period of time to deduct the gMITO tokens
   * @param applyFrom The timestamp to apply the emission from
   */
  function configureValidatorRewardEmission(uint256 rps, uint160 rateMultiplier, uint48 renewalPeriod, uint48 applyFrom)
    external;

  /**
   * @notice Sets the recipient address for the validator reward.
   * @dev This function sets the address that will receive the validator reward.
   * @param recipient The address of the validator reward recipient.
   */
  function setValidatorRewardRecipient(address recipient) external;
}
