// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { EnumerableMap } from '@oz/utils/structs/EnumerableMap.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IEpochFeeder } from '../../interfaces/hub/validator/IEpochFeeder.sol';
import { IValidatorContributionFeed } from '../../interfaces/hub/validator/IValidatorContributionFeed.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { StdError } from '../../lib/StdError.sol';

/// @title ValidatorContributionFeed
/// @dev Report lifecycle:
/// 1. initializeReport
/// 2. pushValidatorWeights
/// 3-1. finalizeReport
/// 3-2. revokeReport -> Back to step 1
contract ValidatorContributionFeed is
  IValidatorContributionFeed,
  Ownable2StepUpgradeable,
  AccessControlEnumerableUpgradeable,
  UUPSUpgradeable
{
  using ERC7201Utils for string;
  using SafeCast for uint256;
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  struct ReportChecker {
    uint128 totalWeight;
    uint16 numOfValidators; // max 65535
    uint112 _reserved;
  }

  struct Reward {
    ReportStatus status;
    uint248 totalWeight;
    ValidatorWeight[] weights;
    mapping(address valAddr => uint256 index) weightByValAddr;
  }

  struct StorageV1 {
    uint256 nextEpoch;
    ReportChecker checker;
    mapping(uint256 epoch => Reward reward) rewards;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ValidatorContributionFeedStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // ========================================== END STORAGE LAYOUT ========================================== //

  /// @notice keccak256('mitosis.role.ValidatorContributionFeed.feeder')
  bytes32 public constant FEEDER_ROLE = 0xa33b22848ec080944b3c811b3fe6236387c5104ce69ccd386b545a980fbe6827;
  uint256 public constant MAX_WEIGHTS_PER_ACTION = 1000;

  IEpochFeeder private immutable _epochFeeder;

  constructor(IEpochFeeder epochFeeder_) {
    _disableInitializers();

    _epochFeeder = epochFeeder_;
  }

  function initialize(address owner_) external initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(owner_);
    __Ownable2Step_init();
    __AccessControl_init();
    __AccessControlEnumerable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, owner_);

    StorageV1 storage $ = _getStorageV1();

    $.nextEpoch = 1;
  }

  /// @inheritdoc IValidatorContributionFeed
  function epochFeeder() external view returns (IEpochFeeder) {
    return _epochFeeder;
  }

  /// @inheritdoc IValidatorContributionFeed
  function weightCount(uint256 epoch) external view returns (uint256) {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);

    return _weightCount(reward);
  }

  /// @inheritdoc IValidatorContributionFeed
  function weightAt(uint256 epoch, uint256 index) external view returns (ValidatorWeight memory) {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);

    return reward.weights[index + 1];
  }

  /// @inheritdoc IValidatorContributionFeed
  function weightOf(uint256 epoch, address valAddr) external view returns (ValidatorWeight memory, bool) {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);

    uint256 index = reward.weightByValAddr[valAddr];
    if (index == 0) {
      ValidatorWeight memory empty;
      return (empty, false);
    }
    return (reward.weights[index], true);
  }

  /// @inheritdoc IValidatorContributionFeed
  function available(uint256 epoch) external view returns (bool) {
    return _getStorageV1().rewards[epoch].status == ReportStatus.FINALIZED;
  }

  /// @inheritdoc IValidatorContributionFeed
  function summary(uint256 epoch) external view returns (Summary memory) {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);

    return Summary({
      totalWeight: uint256(reward.totalWeight).toUint128(),
      numOfValidators: _weightCount(reward).toUint128()
    });
  }

  /// @inheritdoc IValidatorContributionFeed
  function initializeReport(InitReportRequest calldata request) external onlyRole(FEEDER_ROLE) {
    StorageV1 storage $ = _getStorageV1();

    uint256 epoch = $.nextEpoch;

    require(epoch < _epochFeeder.epoch(), StdError.InvalidParameter('epoch'));

    Reward storage reward = $.rewards[epoch];
    require(reward.status == ReportStatus.NONE, IValidatorContributionFeed__InvalidReportStatus());

    reward.status = ReportStatus.INITIALIZED;
    reward.totalWeight = request.totalWeight;
    $.checker.numOfValidators = request.numOfValidators;
    // 0 index is reserved for empty slot
    {
      ValidatorWeight memory empty;
      reward.weights.push(empty);
    }

    emit ReportInitialized(epoch, request.totalWeight, request.numOfValidators);
  }

  /// @inheritdoc IValidatorContributionFeed
  function pushValidatorWeights(ValidatorWeight[] calldata weights) external onlyRole(FEEDER_ROLE) {
    require(weights.length > 0, IValidatorContributionFeed__InvalidWeightCount());
    require(weights.length <= MAX_WEIGHTS_PER_ACTION, IValidatorContributionFeed__InvalidWeightCount());

    StorageV1 storage $ = _getStorageV1();
    uint256 epoch = $.nextEpoch;

    Reward storage reward = $.rewards[epoch];
    require(reward.status == ReportStatus.INITIALIZED, IValidatorContributionFeed__InvalidReportStatus());

    ReportChecker memory checker = $.checker;

    uint256 weightsLen = reward.weights.length;
    uint256 pushWeightsLen = weights.length;
    for (uint256 i = 0; i < pushWeightsLen; i++) {
      ValidatorWeight memory weight = weights[i];
      uint256 index = reward.weightByValAddr[weight.addr];
      require(index == 0, IValidatorContributionFeed__InvalidWeightAddress());

      reward.weights.push(weight);
      reward.weightByValAddr[weight.addr] = weightsLen + i;
      checker.totalWeight += weight.weight;
    }

    uint128 prevTotalWeight = $.checker.totalWeight;
    $.checker = checker;

    emit WeightsPushed(epoch, checker.totalWeight - prevTotalWeight, pushWeightsLen.toUint16());
  }

  /// @inheritdoc IValidatorContributionFeed
  function finalizeReport() external onlyRole(FEEDER_ROLE) {
    StorageV1 storage $ = _getStorageV1();
    uint256 epoch = $.nextEpoch;

    Reward storage reward = $.rewards[epoch];
    require(reward.status == ReportStatus.INITIALIZED, IValidatorContributionFeed__InvalidReportStatus());

    ReportChecker memory checker = $.checker;
    require(checker.totalWeight == reward.totalWeight, IValidatorContributionFeed__InvalidTotalWeight());
    require(checker.numOfValidators == _weightCount(reward), IValidatorContributionFeed__InvalidValidatorCount());

    reward.status = ReportStatus.FINALIZED;

    $.nextEpoch++;
    delete $.checker;

    emit ReportFinalized(epoch);
  }

  /// @inheritdoc IValidatorContributionFeed
  function revokeReport() external onlyRole(FEEDER_ROLE) {
    StorageV1 storage $ = _getStorageV1();
    uint256 epoch = $.nextEpoch;

    Reward storage reward = $.rewards[epoch];
    require(
      reward.status == ReportStatus.INITIALIZED || reward.status == ReportStatus.REVOKING,
      IValidatorContributionFeed__InvalidReportStatus()
    );

    // NOTICE: we need to separate revoke sequence because of the gas limit
    uint256 removeCount = Math.min(MAX_WEIGHTS_PER_ACTION, reward.weights.length);
    for (uint256 i = 0; i < removeCount; i++) {
      ValidatorWeight memory weight = reward.weights[reward.weights.length - 1];
      delete reward.weightByValAddr[weight.addr];
      reward.weights.pop();
    }

    if ($.rewards[epoch].weights.length > 0) {
      reward.status = ReportStatus.REVOKING;
      emit ReportRevoking(epoch);
      return;
    }

    delete $.rewards[epoch].weights;
    delete $.rewards[epoch];
    delete $.checker;

    emit ReportRevoked(epoch);
  }

  // ================== INTERNAL FUNCTIONS ================== //

  function _weightCount(Reward storage reward) internal view returns (uint256) {
    return reward.weights.length - 1;
  }

  function _assertReportReady(Reward storage reward) internal view {
    require(reward.status == ReportStatus.FINALIZED, IValidatorContributionFeed__ReportNotReady());
  }

  // ================== UUPS ================== //

  function _authorizeUpgrade(address) internal view override onlyOwner { }
}
