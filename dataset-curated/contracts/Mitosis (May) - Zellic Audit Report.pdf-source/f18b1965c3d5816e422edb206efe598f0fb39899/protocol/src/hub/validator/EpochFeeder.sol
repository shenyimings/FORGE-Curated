// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { Time } from '@oz/utils/types/Time.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IEpochFeeder } from '../../interfaces/hub/validator/IEpochFeeder.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { StdError } from '../../lib/StdError.sol';

contract EpochFeederStorageV1 {
  using ERC7201Utils for string;

  struct Checkpoint {
    uint160 epoch;
    uint48 interval;
    uint48 timestamp;
  }

  struct StorageV1 {
    Checkpoint[] history;
  }

  string private constant _NAMESPACE = 'mitosis.storage.EpochFeeder';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}

/**
 * @title EpochFeeder
 * @notice Manages epoch transitions and timing for the protocol
 * @dev This contract is upgradeable using UUPS pattern
 */
contract EpochFeeder is IEpochFeeder, EpochFeederStorageV1, Ownable2StepUpgradeable, UUPSUpgradeable {
  using SafeCast for uint256;

  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, uint48 initialEpochTime_, uint48 interval_) external initializer {
    require(block.timestamp < initialEpochTime_, StdError.InvalidParameter('initialEpochTime'));

    __UUPSUpgradeable_init();
    __Ownable_init(owner_);
    __Ownable2Step_init();

    StorageV1 storage $ = _getStorageV1();
    $.history.push(Checkpoint({ epoch: 0, interval: 0, timestamp: 0 }));
    $.history.push(Checkpoint({ epoch: 1, interval: interval_, timestamp: initialEpochTime_ }));
  }

  /// @inheritdoc IEpochFeeder
  function epoch() external view returns (uint256) {
    return _epochAt(_getStorageV1(), Time.timestamp());
  }

  /// @inheritdoc IEpochFeeder
  function epochAt(uint48 timestamp_) external view returns (uint256) {
    return _epochAt(_getStorageV1(), timestamp_);
  }

  /// @inheritdoc IEpochFeeder
  function time() external view returns (uint48) {
    StorageV1 storage $ = _getStorageV1();
    return _timeAt($, _epochAt($, Time.timestamp()));
  }

  /// @inheritdoc IEpochFeeder
  function timeAt(uint256 epoch_) public view returns (uint48) {
    return _timeAt(_getStorageV1(), epoch_);
  }

  /// @inheritdoc IEpochFeeder
  function interval() public view returns (uint48) {
    StorageV1 storage $ = _getStorageV1();
    uint256 currentEpoch = _epochAt($, Time.timestamp());
    return _intervalAt($, currentEpoch);
  }

  /// @inheritdoc IEpochFeeder
  function intervalAt(uint256 epoch_) public view returns (uint48) {
    return _intervalAt(_getStorageV1(), epoch_);
  }

  /// @inheritdoc IEpochFeeder
  function setNextInterval(uint48 interval_) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    Checkpoint memory lastCheckpoint = $.history[$.history.length - 1];

    uint48 now_ = Time.timestamp();
    (uint256 nextEpoch, uint48 nextEpochTime) = _calculateNextEpochAndTime($, lastCheckpoint, now_);

    if (lastCheckpoint.timestamp <= now_) {
      $.history.push(Checkpoint({ epoch: nextEpoch.toUint160(), interval: interval_, timestamp: nextEpochTime }));
    } else {
      $.history[$.history.length - 1].interval = interval_;
    }

    emit NextIntervalSet(nextEpoch, nextEpochTime, interval_);
  }

  function _calculateNextEpochAndTime(StorageV1 storage $, Checkpoint memory lastCheckpoint, uint48 now_)
    private
    view
    returns (uint256 nextEpoch, uint48 nextEpochTime)
  {
    if (lastCheckpoint.timestamp <= now_) {
      uint256 currentEpoch = _epochAt($, now_);
      nextEpoch = currentEpoch + 1;
      nextEpochTime = lastCheckpoint.timestamp + (currentEpoch * lastCheckpoint.interval).toUint48();
    } else {
      nextEpoch = lastCheckpoint.epoch;
      nextEpochTime = lastCheckpoint.timestamp;
    }
  }

  function _epochAt(StorageV1 storage $, uint48 timestamp_) internal view returns (uint256) {
    Checkpoint memory checkpoint = _upperLookup($.history, _compareTimestamp, timestamp_);
    if (checkpoint.epoch == 0) return 0;
    return checkpoint.epoch + (timestamp_ - checkpoint.timestamp) / checkpoint.interval;
  }

  function _timeAt(StorageV1 storage $, uint256 epoch_) internal view returns (uint48) {
    if (epoch_ == 0) return 0;

    Checkpoint memory checkpoint = _upperLookup($.history, _compareEpoch, epoch_);
    if (epoch_ == checkpoint.epoch) return checkpoint.timestamp;
    return checkpoint.timestamp + ((epoch_ - checkpoint.epoch) * checkpoint.interval).toUint48();
  }

  function _intervalAt(StorageV1 storage $, uint256 epoch_) internal view returns (uint48) {
    if (epoch_ == 0) return 0;

    Checkpoint memory checkpoint = _upperLookup($.history, _compareEpoch, epoch_);
    if (epoch_ == checkpoint.epoch) return checkpoint.interval;
    return checkpoint.interval;
  }

  function _upperLookup(
    Checkpoint[] storage self,
    function(Checkpoint memory, uint256) pure returns (bool) compare,
    uint256 key
  ) private view returns (Checkpoint memory) {
    uint256 len = self.length;
    if (len == 0) return Checkpoint(0, 0, 0);

    uint256 low = 0;
    uint256 high = len;

    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (compare(self[mid], key)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    if (low == 0) return Checkpoint(0, 0, 0);
    return self[low - 1];
  }

  function _compareTimestamp(Checkpoint memory self, uint256 key) private pure returns (bool) {
    return self.timestamp <= key;
  }

  function _compareEpoch(Checkpoint memory self, uint256 key) private pure returns (bool) {
    return self.epoch <= key;
  }

  // ================== UUPS ================== //

  function _authorizeUpgrade(address) internal view override onlyOwner { }
}
