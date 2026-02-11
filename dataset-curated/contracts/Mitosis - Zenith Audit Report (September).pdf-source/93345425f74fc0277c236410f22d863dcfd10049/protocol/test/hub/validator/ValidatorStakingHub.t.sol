// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ValidatorStakingHub } from '../../../src/hub/validator/ValidatorStakingHub.sol';
import { IConsensusValidatorEntrypoint } from
  '../../../src/interfaces/hub/consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IValidatorStakingHub } from '../../../src/interfaces/hub/validator/IValidatorStakingHub.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract ValidatorStakingHubTest is Toolkit {
  address owner = makeAddr('owner');
  address val1 = makeAddr('val-1');
  address val2 = makeAddr('val-2');
  address user1 = makeAddr('user-1');
  address user2 = makeAddr('user-2');
  address notifier1 = makeAddr('notifier-1');
  address notifier2 = makeAddr('notifier-2');

  MockContract entrypoint;
  ValidatorStakingHub hub;

  function setUp() public {
    entrypoint = new MockContract();
    entrypoint.setCall(IConsensusValidatorEntrypoint.updateExtraVotingPower.selector);

    hub = ValidatorStakingHub(
      _proxy(
        address(new ValidatorStakingHub(IConsensusValidatorEntrypoint(address(entrypoint)))),
        abi.encodeCall(ValidatorStakingHub.initialize, (owner))
      )
    );
  }

  function test_init() public view {
    assertEq(hub.owner(), owner);
    assertEq(address(hub.entrypoint()), address(entrypoint));
  }

  function test_addNotifier() public {
    assertFalse(hub.isNotifier(notifier1));
    assertFalse(hub.isNotifier(notifier2));

    vm.prank(owner);
    hub.addNotifier(notifier1);

    vm.prank(owner);
    hub.addNotifier(notifier2);

    assertTrue(hub.isNotifier(notifier1));
    assertTrue(hub.isNotifier(notifier2));
  }

  function test_removeNotifier() public {
    test_addNotifier();

    vm.prank(owner);
    hub.removeNotifier(notifier1);

    vm.prank(owner);
    hub.removeNotifier(notifier2);

    assertFalse(hub.isNotifier(notifier1));
    assertFalse(hub.isNotifier(notifier2));
  }

  function test_notifyStake() public {
    test_addNotifier();

    vm.prank(makeAddr('wrong'));
    vm.expectRevert(_errNotifierNotRegistered(makeAddr('wrong')));
    hub.notifyStake(val1, user1, 10 ether);

    vm.prank(notifier1);
    hub.notifyStake(val1, user1, 10 ether);
    entrypoint.assertLastCall(abi.encodeCall(IConsensusValidatorEntrypoint.updateExtraVotingPower, (val1, 10 ether)));

    vm.warp(_now48() + 1 days);

    vm.prank(notifier2);
    hub.notifyStake(val2, user1, 10 ether);
    entrypoint.assertLastCall(abi.encodeCall(IConsensusValidatorEntrypoint.updateExtraVotingPower, (val2, 10 ether)));

    vm.warp(_now48() + 1 days);

    uint48 offset = 1 days + 1;

    uint256 expectedStakerTwabDay2 = (20 ether * 1 days) + (10 ether * 1 days);
    uint256 expectedStakerTwabDay1 = 10 ether * (1 days - 1);
    uint256 expectedValidatorTwabVal1Day2 = 10 ether * 2 days;
    uint256 expectedValidatorTwabVal1Day1 = 10 ether * (1 days - 1);
    uint256 expectedValidatorTwabVal2Day2 = 10 ether * 1 days;
    uint256 expectedValidatorTwabVal2Day1 = 0;

    // present

    assertEq(hub.stakerTotal(user1, _now48()), 20 ether);
    assertEq(hub.stakerTotal(user1, _now48() - offset), 10 ether);

    assertEq(hub.validatorTotal(val1, _now48()), 10 ether);
    assertEq(hub.validatorTotal(val2, _now48()), 10 ether);
    assertEq(hub.validatorTotal(val1, _now48() - offset), 10 ether);
    assertEq(hub.validatorTotal(val2, _now48() - offset), 0);

    assertEq(hub.validatorStakerTotal(val1, user1, _now48()), 10 ether);
    assertEq(hub.validatorStakerTotal(val2, user1, _now48()), 10 ether);
    assertEq(hub.validatorStakerTotal(val1, user1, _now48() - offset), 10 ether);
    assertEq(hub.validatorStakerTotal(val2, user1, _now48() - offset), 0);

    // twab

    assertEq(hub.stakerTotalTWAB(user1, _now48()), expectedStakerTwabDay2);
    assertEq(hub.stakerTotalTWAB(user1, _now48() - offset), expectedStakerTwabDay1);

    assertEq(hub.validatorTotalTWAB(val1, _now48()), expectedValidatorTwabVal1Day2);
    assertEq(hub.validatorTotalTWAB(val2, _now48()), expectedValidatorTwabVal2Day2);
    assertEq(hub.validatorTotalTWAB(val1, _now48() - offset), expectedValidatorTwabVal1Day1);
    assertEq(hub.validatorTotalTWAB(val2, _now48() - offset), expectedValidatorTwabVal2Day1);

    assertEq(hub.validatorStakerTotalTWAB(val1, user1, _now48()), expectedValidatorTwabVal1Day2);
    assertEq(hub.validatorStakerTotalTWAB(val2, user1, _now48()), expectedValidatorTwabVal2Day2);
    assertEq(hub.validatorStakerTotalTWAB(val1, user1, _now48() - offset), expectedValidatorTwabVal1Day1);
    assertEq(hub.validatorStakerTotalTWAB(val2, user1, _now48() - offset), expectedValidatorTwabVal2Day1);
  }

  function test_notifyUnstake() public {
    test_addNotifier();

    vm.prank(makeAddr('wrong'));
    vm.expectRevert(_errNotifierNotRegistered(makeAddr('wrong')));
    hub.notifyUnstake(val1, user1, 10 ether);

    // First stake 20 ether
    vm.prank(notifier1);
    hub.notifyStake(val1, user1, 20 ether);
    entrypoint.assertLastCall(abi.encodeCall(IConsensusValidatorEntrypoint.updateExtraVotingPower, (val1, 20 ether)));

    vm.warp(_now48() + 1 days);

    // Then unstake 10 ether
    vm.prank(notifier2);
    hub.notifyUnstake(val1, user1, 10 ether);
    entrypoint.assertLastCall(abi.encodeCall(IConsensusValidatorEntrypoint.updateExtraVotingPower, (val1, 10 ether)));

    vm.warp(_now48() + 1 days);

    uint48 offset = 1 days + 1;

    uint256 expectedStakerTwabDay2 = (10 ether * 1 days) + (20 ether * 1 days);
    uint256 expectedStakerTwabDay1 = 20 ether * (1 days - 1);
    uint256 expectedValidatorTwabDay2 = (10 ether * 1 days) + (20 ether * 1 days);
    uint256 expectedValidatorTwabDay1 = 20 ether * (1 days - 1);

    // present
    assertEq(hub.stakerTotal(user1, _now48()), 10 ether);
    assertEq(hub.stakerTotal(user1, _now48() - offset), 20 ether);

    assertEq(hub.validatorTotal(val1, _now48()), 10 ether);
    assertEq(hub.validatorTotal(val1, _now48() - offset), 20 ether);

    assertEq(hub.validatorStakerTotal(val1, user1, _now48()), 10 ether);
    assertEq(hub.validatorStakerTotal(val1, user1, _now48() - offset), 20 ether);

    // twab
    assertEq(hub.stakerTotalTWAB(user1, _now48()), expectedStakerTwabDay2);
    assertEq(hub.stakerTotalTWAB(user1, _now48() - offset), expectedStakerTwabDay1);

    assertEq(hub.validatorTotalTWAB(val1, _now48()), expectedValidatorTwabDay2);
    assertEq(hub.validatorTotalTWAB(val1, _now48() - offset), expectedValidatorTwabDay1);

    assertEq(hub.validatorStakerTotalTWAB(val1, user1, _now48()), expectedValidatorTwabDay2);
    assertEq(hub.validatorStakerTotalTWAB(val1, user1, _now48() - offset), expectedValidatorTwabDay1);
  }

  function test_notifyRedelegation() public {
    test_addNotifier();

    vm.prank(makeAddr('wrong'));
    vm.expectRevert(_errNotifierNotRegistered(makeAddr('wrong')));
    hub.notifyRedelegation(val1, val2, user1, 10 ether);

    // First stake 20 ether to val1
    vm.prank(notifier1);
    hub.notifyStake(val1, user1, 20 ether);
    entrypoint.assertLastCall(abi.encodeCall(IConsensusValidatorEntrypoint.updateExtraVotingPower, (val1, 20 ether)));

    vm.warp(_now48() + 1 days);

    // Then redelegate 10 ether from val1 to val2
    vm.prank(notifier2);
    hub.notifyRedelegation(val1, val2, user1, 10 ether);
    entrypoint.assertCall(abi.encodeCall(IConsensusValidatorEntrypoint.updateExtraVotingPower, (val2, 10 ether)), 0);
    entrypoint.assertCall(abi.encodeCall(IConsensusValidatorEntrypoint.updateExtraVotingPower, (val1, 10 ether)), 1);

    vm.warp(_now48() + 1 days);

    uint48 offset = 1 days + 1;

    uint256 expectedVal1StakerTwabDay2 = (10 ether * 1 days) + (20 ether * 1 days);
    uint256 expectedVal1StakerTwabDay1 = 20 ether * (1 days - 1);
    uint256 expectedVal2StakerTwabDay2 = 10 ether * 1 days;
    uint256 expectedVal2StakerTwabDay1 = 0;

    // present - val1
    assertEq(hub.stakerTotal(user1, _now48()), 20 ether); // Total stake remains 20 ether
    assertEq(hub.validatorTotal(val1, _now48()), 10 ether); // val1 now has 10 ether
    assertEq(hub.validatorStakerTotal(val1, user1, _now48()), 10 ether);

    // present - val2
    assertEq(hub.validatorTotal(val2, _now48()), 10 ether); // val2 now has 10 ether
    assertEq(hub.validatorStakerTotal(val2, user1, _now48()), 10 ether);

    // past - val1
    assertEq(hub.validatorTotal(val1, _now48() - offset), 20 ether);
    assertEq(hub.validatorStakerTotal(val1, user1, _now48() - offset), 20 ether);

    // past - val2
    assertEq(hub.validatorTotal(val2, _now48() - offset), 0);
    assertEq(hub.validatorStakerTotal(val2, user1, _now48() - offset), 0);

    // twab - val1
    assertEq(hub.validatorTotalTWAB(val1, _now48()), expectedVal1StakerTwabDay2);
    assertEq(hub.validatorStakerTotalTWAB(val1, user1, _now48()), expectedVal1StakerTwabDay2);
    assertEq(hub.validatorTotalTWAB(val1, _now48() - offset), expectedVal1StakerTwabDay1);
    assertEq(hub.validatorStakerTotalTWAB(val1, user1, _now48() - offset), expectedVal1StakerTwabDay1);

    // twab - val2
    assertEq(hub.validatorTotalTWAB(val2, _now48()), expectedVal2StakerTwabDay2);
    assertEq(hub.validatorStakerTotalTWAB(val2, user1, _now48()), expectedVal2StakerTwabDay2);
    assertEq(hub.validatorTotalTWAB(val2, _now48() - offset), expectedVal2StakerTwabDay1);
    assertEq(hub.validatorStakerTotalTWAB(val2, user1, _now48() - offset), expectedVal2StakerTwabDay1);
  }

  function _errNotifierNotRegistered(address notifier) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IValidatorStakingHub.IValidatorStakingHub__NotifierNotRegistered.selector, notifier);
  }
}
