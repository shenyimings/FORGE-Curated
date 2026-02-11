// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Math } from '@oz/utils/math/Math.sol';
import { Time } from '@oz/utils/types/Time.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IConsensusValidatorEntrypoint } from '../../interfaces/hub/consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IValidatorManager } from '../../interfaces/hub/validator/IValidatorManager.sol';
import { IValidatorStakingHub } from '../../interfaces/hub/validator/IValidatorStakingHub.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { LibCheckpoint } from '../../lib/LibCheckpoint.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';

contract ValidatorStakingHubStorage {
  using ERC7201Utils for string;

  struct Notifier {
    bool enabled;
  }

  struct StorageV1 {
    mapping(address notifier => Notifier) notifiers;
    mapping(address staker => LibCheckpoint.TraceTWAB) stakerTotal;
    mapping(address valAddr => LibCheckpoint.TraceTWAB) validatorTotal;
    mapping(address valAddr => mapping(address staker => LibCheckpoint.TraceTWAB)) validatorStakerTotal;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ValidatorStakingHubStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}

contract ValidatorStakingHub is
  IValidatorStakingHub,
  ValidatorStakingHubStorage,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  Versioned
{
  using LibCheckpoint for LibCheckpoint.TraceTWAB;

  IConsensusValidatorEntrypoint private immutable _entrypoint;

  constructor(IConsensusValidatorEntrypoint entrypoint_) {
    _disableInitializers();
    _entrypoint = entrypoint_;
  }

  function initialize(address initialOwner) external initializer {
    __Ownable2Step_init();
    __Ownable_init(initialOwner);
    __UUPSUpgradeable_init();
  }

  /// @inheritdoc IValidatorStakingHub
  function entrypoint() external view returns (IConsensusValidatorEntrypoint) {
    return _entrypoint;
  }

  /// @inheritdoc IValidatorStakingHub
  function isNotifier(address notifier) external view returns (bool) {
    return _getStorageV1().notifiers[notifier].enabled;
  }

  /// @inheritdoc IValidatorStakingHub
  function stakerTotal(address staker, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().stakerTotal[staker];
    return trace.upperLookupRecent(timestamp).amount;
  }

  /// @inheritdoc IValidatorStakingHub
  function stakerTotalTWAB(address staker, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().stakerTotal[staker];
    LibCheckpoint.TWABCheckpoint memory twab = trace.upperLookupRecent(timestamp);
    unchecked {
      return twab.amount * (timestamp - twab.lastUpdate) + twab.twab;
    }
  }

  /// @inheritdoc IValidatorStakingHub
  function validatorTotal(address valAddr, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().validatorTotal[valAddr];
    return trace.upperLookupRecent(timestamp).amount;
  }

  /// @inheritdoc IValidatorStakingHub
  function validatorTotalTWAB(address valAddr, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().validatorTotal[valAddr];
    LibCheckpoint.TWABCheckpoint memory twab = trace.upperLookupRecent(timestamp);
    unchecked {
      return twab.amount * (timestamp - twab.lastUpdate) + twab.twab;
    }
  }

  /// @inheritdoc IValidatorStakingHub
  function validatorStakerTotal(address valAddr, address staker, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().validatorStakerTotal[valAddr][staker];
    return trace.upperLookupRecent(timestamp).amount;
  }

  /// @inheritdoc IValidatorStakingHub
  function validatorStakerTotalTWAB(address valAddr, address staker, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().validatorStakerTotal[valAddr][staker];
    LibCheckpoint.TWABCheckpoint memory twab = trace.upperLookupRecent(timestamp);
    unchecked {
      return twab.amount * (timestamp - twab.lastUpdate) + twab.twab;
    }
  }

  /// @inheritdoc IValidatorStakingHub
  function addNotifier(address notifier) external onlyOwner {
    require(notifier != address(0), IValidatorStakingHub__InvalidNotifier(notifier));

    StorageV1 storage $ = _getStorageV1();
    require(!$.notifiers[notifier].enabled, IValidatorStakingHub__NotifierAlreadyRegistered(notifier));

    $.notifiers[notifier] = Notifier({ enabled: true });

    emit NotifierAdded(notifier);
  }

  /// @inheritdoc IValidatorStakingHub
  function removeNotifier(address notifier) external onlyOwner {
    require(notifier != address(0), IValidatorStakingHub__InvalidNotifier(notifier));

    StorageV1 storage $ = _getStorageV1();
    require($.notifiers[notifier].enabled, IValidatorStakingHub__NotifierNotRegistered(notifier));

    $.notifiers[notifier] = Notifier({ enabled: false });

    emit NotifierRemoved(notifier);
  }

  /// @inheritdoc IValidatorStakingHub
  function notifyStake(address valAddr, address staker, uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    Notifier memory notifier = $.notifiers[_msgSender()];
    require(notifier.enabled, IValidatorStakingHub__NotifierNotRegistered(_msgSender()));

    _stake($, valAddr, staker, amount);

    emit NotifiedStake(valAddr, staker, amount, _msgSender());
  }

  /// @inheritdoc IValidatorStakingHub
  function notifyUnstake(address valAddr, address staker, uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    Notifier memory notifier = $.notifiers[_msgSender()];
    require(notifier.enabled, IValidatorStakingHub__NotifierNotRegistered(_msgSender()));

    _unstake($, valAddr, staker, amount);

    emit NotifiedUnstake(valAddr, staker, amount, _msgSender());
  }

  /// @inheritdoc IValidatorStakingHub
  function notifyRedelegation(address fromValAddr, address toValAddr, address staker, uint256 amount) external {
    require(fromValAddr != toValAddr, IValidatorStakingHub__RedelegatedFromSelf(fromValAddr));
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    Notifier memory notifier = $.notifiers[_msgSender()];
    require(notifier.enabled, IValidatorStakingHub__NotifierNotRegistered(_msgSender()));

    _unstake($, fromValAddr, staker, amount);
    _stake($, toValAddr, staker, amount);

    emit NotifiedRedelegation(fromValAddr, toValAddr, staker, amount, _msgSender());
  }

  // ===================================== INTERNAL FUNCTIONS ===================================== //

  function _stake(StorageV1 storage $, address valAddr, address staker, uint256 amount) internal {
    uint48 now_ = Time.timestamp();

    $.stakerTotal[staker].push(amount, now_, LibCheckpoint.add);
    $.validatorTotal[valAddr].push(amount, now_, LibCheckpoint.add);
    $.validatorStakerTotal[valAddr][staker].push(amount, now_, LibCheckpoint.add);

    _updateExtraVotingPower($, valAddr);
  }

  function _unstake(StorageV1 storage $, address valAddr, address staker, uint256 amount) internal {
    uint48 now_ = Time.timestamp();

    $.stakerTotal[staker].push(amount, now_, LibCheckpoint.sub);
    $.validatorTotal[valAddr].push(amount, now_, LibCheckpoint.sub);
    $.validatorStakerTotal[valAddr][staker].push(amount, now_, LibCheckpoint.sub);

    _updateExtraVotingPower($, valAddr);
  }

  function _updateExtraVotingPower(StorageV1 storage $, address valAddr) internal {
    _entrypoint.updateExtraVotingPower(valAddr, $.validatorTotal[valAddr].last().amount);
  }

  // ========== UUPS ========== //

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
