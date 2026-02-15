// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Arrays } from '@oz/utils/Arrays.sol';
import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { Checkpoints } from '@oz/utils/structs/Checkpoints.sol';

import { CheckpointsExt } from './CheckpointsExt.sol';

library LibQueue {
  using SafeCast for uint256;
  using Checkpoints for Checkpoints.Trace208;
  using CheckpointsExt for Checkpoints.Trace208;
  using Arrays for uint256[];

  // ================================= Trace208OffsetQueue ================================= //

  error LibQueue__NothingToClaim();

  struct Trace208OffsetQueue {
    uint32 _offset;
    // storage reserve for future usage
    uint224 _reserved;
    Checkpoints.Trace208 _items;
  }

  function size(Trace208OffsetQueue storage $) internal view returns (uint32) {
    return $._items.length().toUint32();
  }

  function offset(Trace208OffsetQueue storage $) internal view returns (uint32) {
    return $._offset;
  }

  function itemAt(Trace208OffsetQueue storage $, uint32 pos) internal view returns (uint48, uint208) {
    Checkpoints.Checkpoint208 memory checkpoint = $._items.at(pos);
    return (checkpoint._key, checkpoint._value);
  }

  function valueAt(Trace208OffsetQueue storage $, uint32 pos) internal view returns (uint208) {
    Checkpoints.Checkpoint208 memory checkpoint = $._items.at(pos);
    return checkpoint._value;
  }

  function recentItemAt(Trace208OffsetQueue storage $, uint48 time) internal view returns (uint48, uint208) {
    Checkpoints.Trace208 storage items = $._items;

    uint32 pos = items.upperBinaryLookup(time, 0, items.length()).toUint32();
    if (pos == 0) return (0, 0);

    Checkpoints.Checkpoint208 memory checkpoint = $._items.at(pos - 1);
    return (checkpoint._key, checkpoint._value);
  }

  function pending(Trace208OffsetQueue storage $, uint48 time) internal view returns (uint256, uint256) {
    Checkpoints.Trace208 storage items = $._items;

    uint32 offset_ = $._offset;
    uint256 reqLen = items.length();
    if (reqLen <= offset_) return (0, 0);

    uint32 found = items.upperBinaryLookup(time, offset_, reqLen).toUint32();

    uint208 latestValue = items.latest();
    uint208 offsetValue = offset_ == 0 ? 0 : items.valueAt(offset_ - 1);
    uint256 total = latestValue - offsetValue;
    if (offset_ == found) return (total, 0);

    uint208 foundValue = items.valueAt(found - 1);
    uint256 available = foundValue - offsetValue;
    return (total, available);
  }

  function append(Trace208OffsetQueue storage $, uint48 time, uint208 amount) internal returns (uint32) {
    Checkpoints.Trace208 storage items = $._items;

    uint32 reqId = size($);

    if (reqId == 0) items.push(time, amount);
    else items.push(time, items.latest() + amount);

    return reqId;
  }

  function solveByKey(Trace208OffsetQueue storage $, uint48 key) internal returns (uint32, uint32) {
    Checkpoints.Trace208 storage items = $._items;

    uint32 offset_ = $._offset;
    uint256 reqLen = items.length();
    require(reqLen > offset_, LibQueue__NothingToClaim());

    uint32 found = items.upperBinaryLookup(key, offset_, reqLen).toUint32();
    require(found > offset_, LibQueue__NothingToClaim());

    $._offset = found;

    return (offset_, found);
  }

  function solveByCount(Trace208OffsetQueue storage $, uint256 count) internal returns (uint32, uint32) {
    Checkpoints.Trace208 storage items = $._items;

    uint32 offset_ = $._offset;
    uint256 reqLen = items.length();
    require(reqLen > offset_, LibQueue__NothingToClaim());

    uint32 found = Math.min(offset_ + count, reqLen).toUint32();
    require(found > offset_, LibQueue__NothingToClaim());

    $._offset = found;

    return (offset_, found);
  }

  // ================================= NEW ================================= //

  struct UintOffsetQueue {
    uint32 _offset;
    // storage reserve for future usage
    uint224 _reserved;
    uint256[] _items;
  }

  function size(UintOffsetQueue storage $) internal view returns (uint32) {
    return $._items.length.toUint32();
  }

  function offset(UintOffsetQueue storage $) internal view returns (uint32) {
    return $._offset;
  }

  function itemAt(UintOffsetQueue storage $, uint32 pos) internal view returns (uint256) {
    return $._items[pos];
  }

  function append(UintOffsetQueue storage $, uint256 item) internal returns (uint32) {
    uint32 reqId = size($);

    $._items.push(item);

    return reqId;
  }

  function solveByKey(UintOffsetQueue storage $, uint256 key) internal returns (uint32, uint32) {
    uint256[] storage items = $._items;

    uint32 offset_ = $._offset;
    uint256 reqLen = items.length;
    require(reqLen > offset_, LibQueue__NothingToClaim());

    uint32 found = Arrays.findUpperBound(items, key).toUint32();
    require(found > offset_, LibQueue__NothingToClaim());

    $._offset = found;

    return (offset_, found);
  }

  function solveByCount(UintOffsetQueue storage $, uint256 count) internal returns (uint32, uint32) {
    uint256[] storage items = $._items;

    uint32 offset_ = $._offset;
    uint256 reqLen = items.length;
    require(reqLen > offset_, LibQueue__NothingToClaim());

    uint32 found = Math.min(offset_ + count, reqLen).toUint32();

    $._offset = found;

    return (offset_, found);
  }
}
