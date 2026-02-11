// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { Time } from '@oz/utils/types/Time.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IGovMITO } from '../interfaces/hub/IGovMITO.sol';
import { IGovMITOEmission } from '../interfaces/hub/IGovMITOEmission.sol';
import { IEpochFeeder } from '../interfaces/hub/validator/IEpochFeeder.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { StdError } from '../lib/StdError.sol';

contract GovMITOEmissionStorageV1 {
  using ERC7201Utils for string;

  struct ValidatorRewardEmission {
    uint256 rps;
    uint160 rateMultiplier; // 10000 = 100%
    uint48 renewalPeriod;
    uint48 timestamp;
  }

  struct ValidatorReward {
    ValidatorRewardEmission[] emissions;
    uint256 total;
    uint256 spent;
    address recipient;
  }

  struct StorageV1 {
    ValidatorReward validatorReward;
  }

  string private constant _NAMESPACE = 'mitosis.storage.GovMITOEmission';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}

/// @title GovMITOEmission
/// @notice This contract is used to manage the emission of GovMITO
contract GovMITOEmission is
  IGovMITOEmission,
  GovMITOEmissionStorageV1,
  UUPSUpgradeable,
  Ownable2StepUpgradeable,
  AccessControlEnumerableUpgradeable
{
  using SafeERC20 for IGovMITO;
  using SafeCast for uint256;

  uint256 public constant RATE_DENOMINATOR = 10000;

  /// @notice keccak256('mitosis.role.GovMITOEmission.validatorRewardManager')
  bytes32 public constant VALIDATOR_REWARD_MANAGER_ROLE =
    0x36d3c8b6777fd16fd79f9eef0dbf969583ea790f221ff2956c3152aa8dbed5eb;

  IGovMITO private immutable _govMITO;
  IEpochFeeder private immutable _epochFeeder;

  constructor(IGovMITO govMITO_, IEpochFeeder epochFeeder_) {
    _disableInitializers();

    _govMITO = govMITO_;
    _epochFeeder = epochFeeder_;
  }

  function initialize(address initialOwner, ValidatorRewardConfig memory config) external payable initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(initialOwner);
    __Ownable2Step_init();

    __AccessControl_init();
    __AccessControlEnumerable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
    _setRoleAdmin(VALIDATOR_REWARD_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

    uint48 currentTime = Time.timestamp();
    require(config.startsFrom > currentTime, StdError.InvalidParameter('config.ssf'));

    StorageV1 storage $ = _getStorageV1();

    _configureValidatorRewardEmission($, config.rps, config.rateMultiplier, config.renewalPeriod, config.startsFrom);
    _setValidatorRewardRecipient($, config.recipient);
  }

  /// @inheritdoc IGovMITOEmission
  function govMITO() external view returns (IGovMITO) {
    return _govMITO;
  }

  /// @inheritdoc IGovMITOEmission
  function epochFeeder() external view returns (IEpochFeeder) {
    return _epochFeeder;
  }

  /// @inheritdoc IGovMITOEmission
  function validatorReward(uint256 epoch) external view returns (uint256) {
    return _calcValidatorRewardForEpoch(_getStorageV1(), epoch);
  }

  /// @inheritdoc IGovMITOEmission
  function validatorRewardTotal() external view returns (uint256) {
    return _getStorageV1().validatorReward.total;
  }

  /// @inheritdoc IGovMITOEmission
  function validatorRewardSpent() external view returns (uint256) {
    return _getStorageV1().validatorReward.spent;
  }

  /// @inheritdoc IGovMITOEmission
  function validatorRewardEmissionsCount() external view returns (uint256) {
    return _getStorageV1().validatorReward.emissions.length;
  }

  /// @inheritdoc IGovMITOEmission
  function validatorRewardEmissionsByIndex(uint256 index) external view returns (uint256, uint160, uint48) {
    ValidatorRewardEmission memory emission = _getStorageV1().validatorReward.emissions[index];
    return (emission.rps, emission.rateMultiplier, emission.renewalPeriod);
  }

  /// @inheritdoc IGovMITOEmission
  function validatorRewardEmissionsByTime(uint48 timestamp) external view returns (uint256, uint160, uint48) {
    (uint256 index, bool found) = _upperLookup(_getStorageV1().validatorReward.emissions, timestamp);
    require(found, StdError.InvalidParameter('emission.timestamp'));

    ValidatorRewardEmission memory emission = _getStorageV1().validatorReward.emissions[index];

    uint256 rps = emission.rps;
    uint160 rateMultiplier = emission.rateMultiplier;
    uint48 renewalPeriod = emission.renewalPeriod;

    uint48 lastDeducted = emission.timestamp;
    uint48 endTime = Time.timestamp();

    while (lastDeducted < endTime) {
      uint48 nextDeduction = lastDeducted + renewalPeriod;
      rps = Math.mulDiv(rps, rateMultiplier, RATE_DENOMINATOR);
      lastDeducted = nextDeduction;
    }

    return (rps, rateMultiplier, renewalPeriod);
  }

  /// @inheritdoc IGovMITOEmission
  function validatorRewardRecipient() external view returns (address) {
    return _getStorageV1().validatorReward.recipient;
  }

  /// @inheritdoc IGovMITOEmission
  function requestValidatorReward(uint256 epoch, address recipient, uint256 amount) external returns (uint256) {
    StorageV1 storage $ = _getStorageV1();
    require($.validatorReward.recipient == _msgSender(), StdError.Unauthorized());

    uint256 spent = $.validatorReward.spent;
    require($.validatorReward.total >= spent + amount, NotEnoughReserve());

    $.validatorReward.spent += amount;
    _govMITO.safeTransfer(recipient, amount);

    emit ValidatorRewardRequested(epoch, recipient, amount);

    return amount;
  }

  /// @inheritdoc IGovMITOEmission
  function addValidatorRewardEmission() external payable {
    require(msg.value > 0, StdError.InvalidParameter('msg.value'));

    StorageV1 storage $ = _getStorageV1();

    $.validatorReward.total += msg.value;
    _govMITO.mint{ value: msg.value }(address(this));

    emit ValidatorRewardEmissionAdded(_msgSender(), msg.value);
  }

  function configureValidatorRewardEmission(uint256 rps, uint160 rateMultiplier, uint48 renewalPeriod, uint48 applyFrom)
    external
    onlyRole(VALIDATOR_REWARD_MANAGER_ROLE)
  {
    _configureValidatorRewardEmission(_getStorageV1(), rps, rateMultiplier, renewalPeriod, applyFrom);
  }

  /// @inheritdoc IGovMITOEmission
  function setValidatorRewardRecipient(address recipient) external onlyOwner {
    _setValidatorRewardRecipient(_getStorageV1(), recipient);
  }

  function _configureValidatorRewardEmission(
    StorageV1 storage $,
    uint256 rps,
    uint160 rateMultiplier,
    uint48 renewalPeriod,
    uint48 timestamp
  ) internal {
    uint48 now_ = Time.timestamp();

    require(now_ <= timestamp, StdError.InvalidParameter('timestamp'));
    require(
      $.validatorReward.emissions.length == 0 || timestamp > _latest($.validatorReward.emissions).timestamp,
      StdError.InvalidParameter('timestamp')
    );

    $.validatorReward.emissions.push(
      ValidatorRewardEmission({
        rps: rps,
        rateMultiplier: rateMultiplier,
        renewalPeriod: renewalPeriod,
        timestamp: timestamp
      })
    );

    emit ValidatorRewardEmissionConfigured(rps, rateMultiplier, renewalPeriod, timestamp);
  }

  function _setValidatorRewardRecipient(StorageV1 storage $, address recipient) internal {
    address prevRecipient = $.validatorReward.recipient;
    $.validatorReward.recipient = recipient;
    emit ValidatorRewardRecipientSet(prevRecipient, recipient);
  }

  function _calcRewardForPeriod(
    uint256 rps,
    uint256 rateMultiplier,
    uint48 renewalPeriod,
    uint48 lastDeducted,
    uint48 lastUpdated,
    uint48 endTime
  ) internal pure returns (uint256 reward) {
    if (rps == 0) return 0;
    if (renewalPeriod == 0) return rps * (endTime - lastUpdated);

    while (lastDeducted < endTime) {
      uint48 nextDeduction = lastDeducted + renewalPeriod;
      if (lastUpdated < nextDeduction) {
        uint48 rewardEndTime = Math.min(endTime, nextDeduction).toUint48();
        reward += rps * (rewardEndTime - lastUpdated);
        lastUpdated = rewardEndTime;
      }
      rps = Math.mulDiv(rps, rateMultiplier, RATE_DENOMINATOR);
      lastDeducted = nextDeduction;
    }
  }

  function _calcValidatorRewardForEpoch(StorageV1 storage $, uint256 epoch) internal view returns (uint256) {
    require(0 <= epoch, StdError.InvalidParameter('epoch'));

    uint48 epochStartTime = _epochFeeder.timeAt(epoch);
    uint48 epochEndTime = _epochFeeder.timeAt(epoch + 1);

    ValidatorRewardEmission[] storage emissions = $.validatorReward.emissions;

    uint256 emissionLen = emissions.length;
    (uint256 emissionIndex, bool found) = _upperLookup(emissions, epochStartTime);
    ValidatorRewardEmission memory activeLog = emissions[found ? emissionIndex : 0];
    if (epochEndTime < activeLog.timestamp) return 0; // no hope

    uint48 startTime = activeLog.timestamp < epochStartTime ? epochStartTime : activeLog.timestamp;
    uint256 reward = 0;

    for (; emissionIndex < emissionLen - 1; emissionIndex++) {
      ValidatorRewardEmission memory nextLog = emissions[emissionIndex + 1];
      if (nextLog.timestamp >= epochEndTime) break;

      reward += _calcRewardForPeriod(
        activeLog.rps,
        activeLog.rateMultiplier,
        activeLog.renewalPeriod,
        activeLog.timestamp,
        startTime,
        nextLog.timestamp
      );

      startTime = nextLog.timestamp;
      activeLog = nextLog;
    }

    reward += _calcRewardForPeriod(
      activeLog.rps, //
      activeLog.rateMultiplier,
      activeLog.renewalPeriod,
      activeLog.timestamp,
      startTime,
      epochEndTime
    );

    return reward;
  }

  function _latest(ValidatorRewardEmission[] storage self) internal view returns (ValidatorRewardEmission memory) {
    return self[self.length - 1];
  }

  function _upperLookup(ValidatorRewardEmission[] storage self, uint48 key) private view returns (uint256, bool) {
    if (self.length == 0) return (0, false);
    if (key < self[0].timestamp) return (0, false);

    uint256 low = 0;
    uint256 high = self.length;

    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (self[mid].timestamp > key) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }

    if (high == 0) return (0, false);
    return (high - 1, true);
  }

  // ================== UUPS ================== //

  function _authorizeUpgrade(address) internal view override onlyOwner { }
}
