// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Time } from '@oz/utils/types/Time.sol';
import { OwnableUpgradeable } from '@ozu/access/OwnableUpgradeable.sol';

import { EpochFeeder } from '../../../src/hub/validator/EpochFeeder.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract EpochFeederTest is Toolkit {
  uint48 public constant INTERVAL = 1 days;

  address owner = makeAddr('owner');

  EpochFeeder feeder;

  function setUp() public {
    feeder = EpochFeeder(
      _proxy(
        address(new EpochFeeder()), //
        abi.encodeCall(EpochFeeder.initialize, (owner, _now48() + INTERVAL, INTERVAL))
      )
    );
  }

  function test_init() public view {
    assertEq(feeder.owner(), owner);
    assertEq(feeder.epoch(), 0);
    assertEq(feeder.time(), 0);
    assertEq(feeder.interval(), 0);
  }

  function test_setNextInterval_withNonAppliedEpoch() public {
    assertEq(feeder.intervalAt(0), 0);
    assertEq(feeder.intervalAt(1), INTERVAL);

    vm.prank(owner);
    feeder.setNextInterval(INTERVAL * 2);

    assertEq(feeder.intervalAt(0), 0);
    assertEq(feeder.intervalAt(1), INTERVAL * 2);
  }

  function test_setNextInterval_withAppliedEpoch() public {
    assertEq(feeder.intervalAt(0), 0);
    assertEq(feeder.intervalAt(1), INTERVAL);

    // warp to epoch 1
    vm.warp(_now48() + INTERVAL);

    vm.prank(owner);
    feeder.setNextInterval(INTERVAL * 2);

    assertEq(feeder.intervalAt(0), 0);
    assertEq(feeder.intervalAt(1), INTERVAL);
    assertEq(feeder.intervalAt(2), INTERVAL * 2);

    // try overwrite interval
    vm.prank(owner);
    feeder.setNextInterval(INTERVAL * 3);

    assertEq(feeder.intervalAt(0), 0);
    assertEq(feeder.intervalAt(1), INTERVAL);
    assertEq(feeder.intervalAt(2), INTERVAL * 3);
  }

  function test_setNextInterval_unauthorized() public {
    address randomUser = makeAddr('random-user');

    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomUser));
    vm.prank(randomUser);
    feeder.setNextInterval(INTERVAL * 2);
  }

  function test_epoch_clean() public view {
    uint48 now_ = _now48();
    assertEq(feeder.timeAt(0), 0);

    uint48 epoch1Start = now_ + INTERVAL;
    assertEq(feeder.epochAt(epoch1Start - 1), 0, 'one sec before epoch 1');
    assertEq(feeder.epochAt(epoch1Start), 1, '= epoch 1');
    assertEq(feeder.timeAt(1), epoch1Start);
    assertEq(feeder.epochAt(epoch1Start + 1), 1, 'one sec after epoch 1');

    uint48 epoch2Start = epoch1Start + INTERVAL;
    assertEq(feeder.epochAt(epoch2Start - 1), 1, 'one sec before epoch 2');
    assertEq(feeder.epochAt(epoch2Start), 2, '= epoch 2');
    assertEq(feeder.timeAt(2), epoch2Start);
    assertEq(feeder.epochAt(epoch2Start + 1), 2, 'one sec after epoch 2');

    assertEq(feeder.timeAt(3), epoch2Start + INTERVAL);
  }

  /// with new interval
  function test_epoch_dirty() public {
    uint48 now_ = _now48();
    assertEq(feeder.timeAt(0), 0);

    // warp to epoch 3
    vm.warp(now_ + (INTERVAL * 3));

    vm.prank(owner);
    feeder.setNextInterval(INTERVAL * 2);

    assertEq(feeder.epochAt(now_ + INTERVAL), 1, 'epoch 1');
    assertEq(feeder.timeAt(1), now_ + INTERVAL);
    assertEq(feeder.epochAt(now_ + INTERVAL * 2), 2, 'epoch 2');
    assertEq(feeder.timeAt(2), now_ + INTERVAL * 2);
    assertEq(feeder.epochAt(now_ + INTERVAL * 3), 3, 'epoch 3');
    assertEq(feeder.timeAt(3), now_ + INTERVAL * 3);
    assertEq(feeder.epochAt(now_ + INTERVAL * 4), 4, 'epoch 4');
    // check modified interval
    assertEq(feeder.epochAt(now_ + INTERVAL * 6), 5, 'epoch 5');
    assertEq(feeder.timeAt(5), now_ + INTERVAL * 6);
    assertEq(feeder.epochAt(now_ + INTERVAL * 8), 6, 'epoch 6');
    assertEq(feeder.timeAt(6), now_ + INTERVAL * 8);
  }
}
