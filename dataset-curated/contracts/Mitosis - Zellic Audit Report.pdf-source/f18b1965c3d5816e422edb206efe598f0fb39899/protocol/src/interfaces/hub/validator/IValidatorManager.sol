// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IConsensusValidatorEntrypoint } from '../consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IEpochFeeder } from './IEpochFeeder.sol';

/// @title IValidatorManager
/// @notice Interface for the ValidatorManager contract.
/// @dev This interface defines the actions that operators can perform.
///
/// User Actions
/// 1. Staking (Delegate)
/// 2. Redelegate
/// 3. Unstaking (Undelegate)
///
/// Validator Actions
/// 1. Joining the validator set
/// 2. Deposit collateral
/// 3. Withdraw collateral
/// 4. Unjailing the validator
/// 5. Leaving the validator set = making it inactive, not removing anything
interface IValidatorManager {
  struct GlobalValidatorConfigResponse {
    uint256 initialValidatorDeposit;
    uint256 collateralWithdrawalDelaySeconds;
    uint256 minimumCommissionRate;
    uint96 commissionRateUpdateDelayEpoch;
  }

  struct ValidatorInfoResponse {
    address valAddr;
    bytes pubKey;
    address operator;
    address rewardManager;
    address withdrawalRecipient;
    uint256 commissionRate;
    bytes metadata;
  }

  struct RedelegationsResponse {
    uint96 epoch;
    address fromValAddr;
    address toValAddr;
    address staker;
    uint256 amount;
  }

  struct CreateValidatorRequest {
    address operator;
    address rewardManager;
    address withdrawalRecipient;
    uint256 commissionRate; // bp e.g.) 10000 = 100%
    bytes metadata;
  }

  struct UpdateRewardConfigRequest {
    uint256 commissionRate; // bp e.g.) 10000 = 100%
  }

  struct GenesisValidatorSet {
    bytes pubKey;
    address operator;
    address rewardManager;
    address withdrawalRecipient;
    uint256 commissionRate;
    bytes metadata;
    bytes signature;
    uint256 value;
  }

  struct SetGlobalValidatorConfigRequest {
    uint256 initialValidatorDeposit; // used on creation of the validator
    uint256 collateralWithdrawalDelaySeconds; // in seconds
    uint256 minimumCommissionRate; // bp e.g.) 10000 = 100%
    uint96 commissionRateUpdateDelayEpoch; // in epoch
  }

  event FeeSet(uint256 previousFee, uint256 newFee);
  event FeePaid(uint256 amount);

  event ValidatorCreated(
    address indexed valAddr,
    address indexed operator,
    bytes pubKey,
    uint256 initialDeposit,
    CreateValidatorRequest request
  );
  event CollateralDeposited(address indexed valAddr, address indexed depositor, uint256 amount);
  event CollateralWithdrawn(address indexed valAddr, address indexed recipient, uint256 amount);
  event ValidatorUnjailed(address indexed valAddr);
  event OperatorUpdated(address indexed valAddr, address indexed operator);
  event WithdrawalRecipientUpdated(address indexed valAddr, address indexed operator, address indexed recipient);
  event RewardManagerUpdated(address indexed valAddr, address indexed operator, address indexed rewardManager);
  event MetadataUpdated(address indexed valAddr, address indexed operator, bytes metadata);
  event RewardConfigUpdated(address indexed valAddr, address indexed operator, UpdateRewardConfigRequest request);

  event GlobalValidatorConfigUpdated(SetGlobalValidatorConfigRequest request);
  event EpochFeederUpdated(IEpochFeeder indexed epochFeeder);
  event EntrypointUpdated(IConsensusValidatorEntrypoint indexed entrypoint);

  error IValidatorManager__InsufficientFee();

  // ========== VIEWS ========== //

  function MAX_COMMISSION_RATE() external view returns (uint256);

  function entrypoint() external view returns (IConsensusValidatorEntrypoint);
  function epochFeeder() external view returns (IEpochFeeder);

  function fee() external view returns (uint256);
  function globalValidatorConfig() external view returns (GlobalValidatorConfigResponse memory);

  function validatorPubKeyToAddress(bytes calldata pubKey) external pure returns (address);

  function validatorCount() external view returns (uint256);

  /// @notice Returns the validator address at a given index.
  /// @param index The index (starting from 1) to retrieve the validator address from.
  /// @return valAddr The validator address at the specified index.
  function validatorAt(uint256 index) external view returns (address);
  function isValidator(address valAddr) external view returns (bool);

  function validatorInfo(address valAddr) external view returns (ValidatorInfoResponse memory);
  function validatorInfoAt(uint256 epoch, address valAddr) external view returns (ValidatorInfoResponse memory);

  // ========== VALIDATOR ACTIONS ========== //

  // validator actions
  /// @param pubKey The compressed 33-byte secp256k1 public key of the valAddr.
  function createValidator(bytes calldata pubKey, CreateValidatorRequest calldata request) external payable;
  function unjailValidator(address valAddr) external payable;

  // operator actions
  function depositCollateral(address valAddr) external payable;
  /**
   * @dev Be careful, as the withdrawal recipient, not msg.sender, will receive the collateral.
   */
  function withdrawCollateral(address valAddr, uint256 amount) external payable;

  // operator actions - validator configurations
  function updateOperator(address valAddr, address operator) external;
  function updateWithdrawalRecipient(address valAddr, address withdrawalRecipient) external;
  function updateRewardManager(address valAddr, address rewardManager) external;
  function updateMetadata(address valAddr, bytes calldata metadata) external;
  function updateRewardConfig(address valAddr, UpdateRewardConfigRequest calldata request) external;

  // ========== CONTRACT MANAGEMENT ========== //

  function setFee(uint256 fee) external;
  function setGlobalValidatorConfig(SetGlobalValidatorConfigRequest calldata request) external;
}
