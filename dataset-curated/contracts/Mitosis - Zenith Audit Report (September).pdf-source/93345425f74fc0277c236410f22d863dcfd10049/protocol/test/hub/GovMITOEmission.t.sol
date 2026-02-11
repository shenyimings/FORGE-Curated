// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';

import { GovMITOEmission } from '../../src/hub/GovMITOEmission.sol';
import { IGovMITO } from '../../src/interfaces/hub/IGovMITO.sol';
import { IGovMITOEmission } from '../../src/interfaces/hub/IGovMITOEmission.sol';
import { IEpochFeeder } from '../../src/interfaces/hub/validator/IEpochFeeder.sol';
import { MockContract } from '../util/MockContract.sol';
import { Toolkit } from '../util/Toolkit.sol';

contract GovMITOEmissionTest is Toolkit {
  address owner = makeAddr('owner');
  address recipient = makeAddr('recipient');
  address rewardManager = makeAddr('rewardManager');

  GovMITOEmission emission;
  GovMITOEmission emissionImpl;

  MockContract feeder;
  MockContract govMITO;

  function setUp() public {
    feeder = new MockContract();

    govMITO = new MockContract();
    govMITO.setCall(IGovMITO.mint.selector);

    emissionImpl = new GovMITOEmission(IGovMITO(address(govMITO)), IEpochFeeder(address(feeder)));
  }

  function test_init() public {
    uint256 rps = 1 gwei;
    uint256 total = rps * 365 days * 2;

    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: rps,
        rateMultiplier: 5000, // 50%
        renewalPeriod: 365 days,
        startsFrom: 1 days,
        recipient: recipient
      })
    );

    assertEq(emission.VALIDATOR_REWARD_MANAGER_ROLE(), keccak256('mitosis.role.GovMITOEmission.validatorRewardManager'));

    vm.deal(owner, total);
    emission.addValidatorRewardEmission{ value: total }();

    assertEq(address(emission).balance, total);

    assertEq(address(emission.govMITO()), address(govMITO));
    assertEq(address(emission.epochFeeder()), address(feeder));

    assertEq(emission.validatorRewardTotal(), total);
    assertEq(emission.validatorRewardSpent(), 0);
    assertEq(emission.validatorRewardEmissionsCount(), 1);

    vm.expectRevert(_errInvalidParameter('emission.timestamp'));
    emission.validatorRewardEmissionsByTime(_now48());

    {
      (uint256 rps_, uint160 rateMultiplier, uint48 renewalPeriod) = emission.validatorRewardEmissionsByIndex(0);
      assertEq(rps_, 1 gwei);
      assertEq(rateMultiplier, 5000);
      assertEq(renewalPeriod, 365 days);
    }

    {
      (uint256 rps_, uint160 rateMultiplier, uint48 renewalPeriod) = emission.validatorRewardEmissionsByTime(1 days);
      assertEq(rps_, 1 gwei);
      assertEq(rateMultiplier, 5000);
      assertEq(renewalPeriod, 365 days);
    }

    assertEq(emission.validatorRewardRecipient(), recipient);
  }

  function test_init_invalidParameter() public {
    uint256 rps = 1 gwei;

    vm.expectRevert(_errInvalidParameter('config.ssf'));
    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: rps,
        rateMultiplier: 5000, // 50%
        renewalPeriod: 365 days,
        startsFrom: _now48() - 1,
        recipient: recipient
      })
    );
  }

  function test_addValidatorRewardEmission() public {
    uint256 total = 1 ether;

    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: 1 gwei,
        rateMultiplier: 5000, // 50%
        renewalPeriod: 365 days,
        startsFrom: 1 days,
        recipient: recipient
      })
    );

    vm.deal(owner, total);
    emission.addValidatorRewardEmission{ value: total }();

    assertEq(emission.validatorRewardTotal(), total);

    uint256 amount = 1 ether;
    vm.expectEmit();
    emit IGovMITOEmission.ValidatorRewardEmissionAdded(owner, amount);

    vm.deal(owner, amount);
    vm.prank(owner);
    emission.addValidatorRewardEmission{ value: amount }();

    assertEq(emission.validatorRewardTotal(), total + amount);
    assertEq(address(emission).balance, total + amount);
  }

  function test_requestValidatorReward() public {
    uint256 total = 1 gwei * 365 days * 2;

    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: 1 gwei,
        rateMultiplier: 5000, // 50%
        renewalPeriod: 365 days,
        startsFrom: 1 days,
        recipient: recipient
      })
    );

    vm.deal(owner, total);
    emission.addValidatorRewardEmission{ value: total }();

    assertEq(address(emission).balance, total);

    for (uint256 i = 1; i <= 20; i++) {
      feeder.setRet(abi.encodeCall(IEpochFeeder.timeAt, (i)), false, abi.encode((2 * i - 1) * 1 days));
    }

    vm.expectEmit();
    emit IGovMITOEmission.ValidatorRewardRequested(1, recipient, 1 gwei);

    vm.prank(recipient);
    emission.requestValidatorReward(1, recipient, 1 gwei);

    assertEq(address(emission).balance, total - 1 gwei);
    assertEq(emission.validatorRewardSpent(), 1 gwei);
  }

  /// @dev test query with no config update
  function test_validatorReward_clean() public {
    uint256 total = 1 gwei * 365 days * 2;

    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: 1 gwei,
        rateMultiplier: 5000, // 50%
        renewalPeriod: 4 days,
        startsFrom: 1 days,
        recipient: recipient
      })
    );

    vm.deal(owner, total);
    emission.addValidatorRewardEmission{ value: total }();

    assertEq(address(emission).balance, total);

    for (uint256 i = 1; i <= 20; i++) {
      feeder.setRet(abi.encodeCall(IEpochFeeder.timeAt, (i)), false, abi.encode((2 * i - 1) * 1 days));
    }

    assertEq(emission.validatorReward(1), 1 gwei * 2 days, 'epoch 1-2');
    assertEq(emission.validatorReward(2), 1 gwei * 2 days, 'epoch 2-3');
    assertEq(emission.validatorReward(3), 0.5 gwei * 2 days, 'epoch 3-4');
    assertEq(emission.validatorReward(4), 0.5 gwei * 2 days, 'epoch 4-5');
    assertEq(emission.validatorReward(5), 0.25 gwei * 2 days, 'epoch 5-6');
  }

  /// @dev test query with config update
  function test_validatorReward_dirty() public {
    uint256 total = 1 gwei * 365 days * 2;

    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: 1 gwei,
        rateMultiplier: 5000, // 50%
        renewalPeriod: 4 days,
        startsFrom: 1 days,
        recipient: recipient
      })
    );

    vm.startPrank(owner);

    vm.deal(owner, total);
    emission.addValidatorRewardEmission{ value: total }();
    emission.grantRole(emission.VALIDATOR_REWARD_MANAGER_ROLE(), rewardManager);

    assertEq(emission.validatorRewardTotal(), total);

    vm.expectRevert(_errAccessControlUnauthorized(owner, emission.VALIDATOR_REWARD_MANAGER_ROLE()));
    emission.configureValidatorRewardEmission(2 gwei, 7500, 2 days, 6 days);

    vm.stopPrank();

    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(2 gwei, 7500, 2 days, 6 days);

    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(1 gwei, 20000, 4 days, 10 days);

    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(0, 0, 0, 15 days);

    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(1 gwei, 10000, 1 days, 17 days);

    for (uint256 i = 1; i <= 20; i++) {
      feeder.setRet(abi.encodeCall(IEpochFeeder.timeAt, (i)), false, abi.encode((2 * i - 1) * 1 days));
    }

    assertEq(emission.validatorReward(1), 1 gwei * 2 days, 'epoch 1-2');
    assertEq(emission.validatorReward(2), 1 gwei * 2 days, 'epoch 2-3');
    assertEq(emission.validatorReward(3), (0.5 gwei * 1 days) + (2 gwei * 1 days), 'epoch 3-4');
    assertEq(emission.validatorReward(4), (2 gwei * 1 days) + (1.5 gwei * 1 days), 'epoch 4-5');
    assertEq(emission.validatorReward(5), (1.5 gwei * 1 days) + (1 gwei * 1 days), 'epoch 5-6');
    assertEq(emission.validatorReward(6), (1 gwei * 2 days), 'epoch 6-7');
    assertEq(emission.validatorReward(7), (1 gwei * 1 days) + (2 gwei * 1 days), 'epoch 7-8');
    assertEq(emission.validatorReward(8), 0, 'epoch 8-9');
    assertEq(emission.validatorReward(9), 1 gwei * 2 days, 'epoch 9-10');
  }

  function test_stop_renewal() public {
    uint48 now_ = 1000;
    vm.warp(now_);

    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: 1 gwei,
        rateMultiplier: 10_000,
        renewalPeriod: 500,
        startsFrom: now_ + 1,
        recipient: recipient
      })
    );

    vm.startPrank(owner);
    emission.grantRole(emission.VALIDATOR_REWARD_MANAGER_ROLE(), rewardManager);
    vm.stopPrank();

    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(1 gwei, 10_000, 0, 2000);

    uint256 rps;
    uint160 rateMultiplier;
    uint48 renewalPeriod;

    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByTime(now_ + 1);
    assertEq(rps, 1 gwei);
    assertEq(rateMultiplier, 10_000);
    assertEq(renewalPeriod, 500);

    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByTime(now_ + 500);
    assertEq(rps, 1 gwei);
    assertEq(rateMultiplier, 10_000);
    assertEq(renewalPeriod, 500);

    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByTime(now_ + 1000);
    assertEq(rps, 1 gwei);
    assertEq(rateMultiplier, 10_000);
    assertEq(renewalPeriod, 0);

    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByTime(now_ + 1500);
    assertEq(rps, 1 gwei);
    assertEq(rateMultiplier, 10_000);
    assertEq(renewalPeriod, 0);
  }

  function test_configureValidatorRewardEmission() public {
    uint48 now_ = 1000;
    vm.warp(now_);

    _init(
      IGovMITOEmission.ValidatorRewardConfig({
        rps: 1 gwei,
        rateMultiplier: 5000, // 50%
        renewalPeriod: 365 days,
        startsFrom: 2000,
        recipient: recipient
      })
    );

    vm.startPrank(owner);
    emission.grantRole(emission.VALIDATOR_REWARD_MANAGER_ROLE(), rewardManager);
    vm.stopPrank();

    uint256 emissionCount = 1;
    uint256 rps;
    uint160 rateMultiplier;
    uint48 renewalPeriod;

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(emissionCount - 1);
    require(rps == 1 gwei, 'rps');
    require(rateMultiplier == 5000, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Overwrite: (now)[2000]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(5 gwei, 10000, 365 days, 2000);

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(emissionCount - 1);
    require(rps == 5 gwei, 'rps');
    require(rateMultiplier == 10000, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Abnormal Push: (now)[2000]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(1 gwei, 10000, 365 days, 1500);

    // Abnormal Push: (now)[2000]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(1 gwei, 10000, 365 days, 500);

    // Push: (now)[2000, 2100]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(1 gwei, 10000, 365 days, 2100);
    emissionCount++;

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(emissionCount - 1);
    require(rps == 1 gwei, 'rps');
    require(rateMultiplier == 10000, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Abnormal Push: (now)[2000, 2100]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(1 gwei, 10000, 365 days, 2050);

    // Overwrite: (now)[2000, 2100]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(5 gwei, 8000, 365 days, 2100);

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(emissionCount - 1);
    require(rps == 5 gwei, 'rps');
    require(rateMultiplier == 8000, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Push: (now)[2000, 2100, 2200]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(1 gwei, 5000, 365 days, 2200);
    emissionCount++;

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(emissionCount - 1);
    require(rps == 1 gwei, 'rps');
    require(rateMultiplier == 5000, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Overwrite: (now)[2000, 2100, 2200]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(100 gwei, 10000, 365 days, 2000);

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(0);
    require(rps == 100 gwei, 'rps');
    require(rateMultiplier == 10000, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Move to 2050
    vm.warp(2050);

    // Push: [2000(now), 2100, 2200, 2300]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(1 gwei, 7500, 365 days, 2300);
    emissionCount++;

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(emissionCount - 1);
    require(rps == 1 gwei, 'rps');
    require(rateMultiplier == 7500, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Abnormal Push: [2000(now), 2100, 2200, 2300]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(1 gwei, 7500, 365 days, 2150);

    // Abnormal Overwrite: [2000(now), 2100, 2200, 2300]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(1 gwei, 5000, 365 days, 2000);

    // Overwrite: [2000(now), 2100, 2200, 2300]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(100 gwei, 10000, 365 days, 2100);

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(1);
    require(rps == 100 gwei, 'rps');
    require(rateMultiplier == 10000, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Move to 2500
    vm.warp(2500);

    // Abnormal Push: [2000, 2100, 2200, 2300(now)]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(50 gwei, 5000, 365 days, 2500);

    // Abnormal Overwrite: [2000, 2100, 2200, 2300(now)]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(15 gwei, 5000, 365 days, 2500);

    // Push: [2000, 2100, 2200, 2300(now), 2501]
    vm.prank(rewardManager);
    emission.configureValidatorRewardEmission(15 gwei, 7500, 365 days, 2501);
    emissionCount++;

    require(emission.validatorRewardEmissionsCount() == emissionCount, 'emissionCount');
    (rps, rateMultiplier, renewalPeriod) = emission.validatorRewardEmissionsByIndex(emissionCount - 1);
    require(rps == 15 gwei, 'rps');
    require(rateMultiplier == 7500, 'rateMultiplier');
    require(renewalPeriod == 365 days, 'renewalPeriod');

    // Move to 2501
    vm.warp(2501);

    // Abnormal Overwrite: [2000, 2100, 2200, 2300, 2501(now)]
    vm.prank(rewardManager);
    vm.expectRevert(_errInvalidParameter('timestamp'));
    emission.configureValidatorRewardEmission(15 gwei, 5000, 365 days, 2501);
  }

  function _init(IGovMITOEmission.ValidatorRewardConfig memory config) private {
    vm.startPrank(owner);
    emission = GovMITOEmission(
      _proxy(
        address(emissionImpl), //
        abi.encodeCall(GovMITOEmission.initialize, (owner, config))
      )
    );
    vm.stopPrank();
  }
}
