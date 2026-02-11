// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { Time } from '@oz/utils/types/Time.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { EpochFeeder } from '../../../src/hub/validator/EpochFeeder.sol';
import { ValidatorRewardDistributor } from '../../../src/hub/validator/ValidatorRewardDistributor.sol';
import { ValidatorStakingHub } from '../../../src/hub/validator/ValidatorStakingHub.sol';
import { IConsensusValidatorEntrypoint } from
  '../../../src/interfaces/hub/consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IGovMITO } from '../../../src/interfaces/hub/IGovMITO.sol';
import { IGovMITOEmission } from '../../../src/interfaces/hub/IGovMITOEmission.sol';
import { IEpochFeeder } from '../../../src/interfaces/hub/validator/IEpochFeeder.sol';
import { IValidatorContributionFeed } from '../../../src/interfaces/hub/validator/IValidatorContributionFeed.sol';
import { IValidatorManager } from '../../../src/interfaces/hub/validator/IValidatorManager.sol';
import { IValidatorRewardDistributor } from '../../../src/interfaces/hub/validator/IValidatorRewardDistributor.sol';
import { IValidatorStaking } from '../../../src/interfaces/hub/validator/IValidatorStaking.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract MockGovMITOEmission is MockContract {
  function requestValidatorReward(uint256, address, uint256 amount) external pure returns (uint256) {
    return amount;
  }
}

contract ValidatorRewardDistributorTest is Toolkit {
  using SafeCast for uint256;
  using LibString for *;

  address _owner = makeAddr('owner');

  MockContract _govMITO;
  MockGovMITOEmission _govMITOEmission;
  MockContract _validatorManager;
  MockContract _epochFeed;
  MockContract _contributionFeed;
  ValidatorStakingHub _stakingHub;
  ValidatorRewardDistributor _distributor;

  uint256 snapshotId;

  function setUp() public {
    _govMITO = new MockContract();
    _govMITOEmission = new MockGovMITOEmission();
    _validatorManager = new MockContract();
    _epochFeed = new MockContract();
    _contributionFeed = new MockContract();

    _stakingHub = ValidatorStakingHub(
      _proxy(
        address(new ValidatorStakingHub(IConsensusValidatorEntrypoint(address(new MockContract())))),
        abi.encodeCall(ValidatorStakingHub.initialize, (_owner))
      )
    );

    _distributor = ValidatorRewardDistributor(
      _proxy(
        address(
          new ValidatorRewardDistributor(
            address(_epochFeed),
            address(_validatorManager),
            address(_stakingHub),
            address(_contributionFeed),
            address(_govMITOEmission)
          )
        ),
        abi.encodeCall(
          ValidatorRewardDistributor.initialize,
          (
            _owner,
            32, // maxClaimEpochs
            1000, // maxStakerBatchSize
            1000 // maxOperatorBatchSize
          )
        )
      )
    );

    vm.prank(_owner);
    _stakingHub.addNotifier(address(this));

    snapshotId = vm.snapshotState();
  }

  function test_init() public view {
    assertEq(_distributor.owner(), _owner);
    assertEq(address(_distributor.epochFeeder()), address(_epochFeed));
    assertEq(address(_distributor.validatorManager()), address(_validatorManager));
    assertEq(address(_distributor.validatorStakingHub()), address(_stakingHub));
    assertEq(address(_distributor.validatorContributionFeed()), address(_contributionFeed));
    assertEq(address(_distributor.govMITOEmission()), address(_govMITOEmission));

    IValidatorRewardDistributor.ClaimConfigResponse memory claimConfig = _distributor.claimConfig();
    assertEq(claimConfig.maxClaimEpochs, 32);
    assertEq(claimConfig.maxStakerBatchSize, 1000);
    assertEq(claimConfig.maxOperatorBatchSize, 1000);
  }

  struct EpochParam {
    uint256 epoch;
    uint256 startsAt;
    uint256 endsAt;
    bool available;
    uint256 totalReward;
    ValidatorParam[] validatorParams;
  }

  struct ValidatorParam {
    // ValidatorManager
    address valAddr;
    address operatorAddr;
    address rewardManager;
    address withdrawalRecipient;
    uint256 commissionRate;
    // ValidatorStakingHub
    address[] stakers;
    uint256[] amounts;
    // ValidatorContributionFeed
    uint96 weight;
    uint128 collateralRewardShare;
    uint128 delegationRewardShare;
  }

  function test_claim_rewards() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 50, stakers: 50, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 55 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 45 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 55 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 45 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
  }

  function test_claim_rewards_by_multiple_validator() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](2);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 80,
      delegationRewardShare: 20
    });
    validatorParams[1] = ValidatorParam({
      valAddr: makeAddr('val-2'),
      operatorAddr: makeAddr('operator-2'),
      rewardManager: makeAddr('rewardManager-2'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-2'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;

    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    validatorParams[1].stakers = stakers;
    validatorParams[1].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // total reward: 100 => val-1 50, val-2 50
    // val-1: operator 80 %, stakers 20%, commission: 10%
    // val-2: operator 50 %, stakers 50%, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 41 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 9 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 41 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 9 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 27.5 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 22.5 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-2'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-2')), 27.5 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-2')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-2')), 22.5 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-2')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-2')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-2')), 1);
  }

  function test_claim_rewards_by_multiple_validator_diff_weight() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](2);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 70,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    validatorParams[1] = ValidatorParam({
      valAddr: makeAddr('val-2'),
      operatorAddr: makeAddr('operator-2'),
      rewardManager: makeAddr('rewardManager-2'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-2'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 30,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;

    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    validatorParams[1].stakers = stakers;
    validatorParams[1].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // total reward: 100 => val-1 70, val-2 30
    //
    // val-1: operator 80 %, stakers 20%, commission: 10%
    // val-2: operator 50 %, stakers 50%, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 38.5 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 31.5 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 38.5 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 31.5 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 16.5 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 13.5 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-2'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-2')), 16.5 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-2')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-2')), 13.5 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-2')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
  }

  function test_claim_rewards_by_multiple_stakers() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    uint96[] memory validatorWeights = new uint96[](1);
    validatorWeights[0] = 100;
    uint128[] memory validatorCollateralRewardShare = new uint128[](1);
    validatorCollateralRewardShare[0] = 50;
    uint128[] memory validatorDelegationRewardShare = new uint128[](1);
    validatorDelegationRewardShare[0] = 50;

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });

    address[] memory stakers = new address[](3);
    uint256[] memory amounts = new uint256[](3);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 50;
    stakers[1] = makeAddr('staker-2');
    amounts[1] = 25;
    stakers[2] = makeAddr('staker-3');
    amounts[2] = 25;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 50, stakers: 50, commission: 10%
    //
    // staker1: 50%, staker2: 25%, staker3: 25%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 55 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 22.5 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-2'), makeAddr('val-1'));
    assertEq(claimable, 11.25 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-3'), makeAddr('val-1'));
    assertEq(claimable, 11.25 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 55 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 22.5 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-2'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-2'), makeAddr('val-1')), 11.25 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-2'), makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-3'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-3'), makeAddr('val-1')), 11.25 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-3'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-2'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-3'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-2'), makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-3'), makeAddr('val-1')), 1);
  }

  function test_claim_rewards_by_diff_collateral() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 80,
      delegationRewardShare: 20
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 80, stakers: 20, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 82 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 18 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 82 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 18 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
  }

  function test_claim_multiple_epoch() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](2);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });
    epochParams[1] = EpochParam({
      epoch: 2,
      startsAt: 200,
      endsAt: 300,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;
    epochParams[1].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // epoch1: 100, epoch1: 100
    // epoch1) val1) operator: 50, stakers: 50, commission: 10%
    // epoch2) val1) operator: 50, stakers: 50, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 110 ether);
    assertEq(nextEpoch, 3);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 90 ether);
    assertEq(nextEpoch, 3);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 110 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 90 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 3);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 3);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 2);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 2);
  }

  function test_claim_multiple_epoch_multiple_validator() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](2);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });
    epochParams[1] = EpochParam({
      epoch: 2,
      startsAt: 200,
      endsAt: 300,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory epoch1_validatorParams = new ValidatorParam[](2);
    ValidatorParam[] memory epoch2_validatorParams = new ValidatorParam[](2);

    epoch1_validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 80,
      delegationRewardShare: 20
    });
    epoch1_validatorParams[1] = ValidatorParam({
      valAddr: makeAddr('val-2'),
      operatorAddr: makeAddr('operator-2'),
      rewardManager: makeAddr('rewardManager-2'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-2'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });

    epoch2_validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    epoch2_validatorParams[1] = ValidatorParam({
      valAddr: makeAddr('val-2'),
      operatorAddr: makeAddr('operator-2'),
      rewardManager: makeAddr('rewardManager-2'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-2'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });

    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;

    epoch1_validatorParams[0].stakers = stakers;
    epoch1_validatorParams[0].amounts = amounts;
    epoch1_validatorParams[1].stakers = stakers;
    epoch1_validatorParams[1].amounts = amounts;

    epoch2_validatorParams[0].stakers = stakers;
    epoch2_validatorParams[0].amounts = amounts;
    epoch2_validatorParams[1].stakers = stakers;
    epoch2_validatorParams[1].amounts = amounts;

    epochParams[0].validatorParams = epoch1_validatorParams;
    epochParams[1].validatorParams = epoch2_validatorParams;

    _setUpEpochs(epochParams);

    // epoch1: 100, epoch2: 100
    // epoch1) operator: 80%, staker: 20%, commission: 10%
    //
    //
    //
    // epoch1) val1) operator: 80%, stakers: 20%, commission: 10%
    // epoch1) val2) operator: 50%, stakers: 50%, commission: 10%
    // epoch2) val1) operator: 50%, stakers: 50%, commission: 10%
    // epoch2) val2) operator: 50%, stakers: 50%, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 68.5 ether);
    assertEq(nextEpoch, 3);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 31.5 ether);
    assertEq(nextEpoch, 3);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 55 ether);
    assertEq(nextEpoch, 3);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 45 ether);
    assertEq(nextEpoch, 3);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 68.5 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 31.5 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 3);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 3);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 2);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 2);

    vm.startPrank(makeAddr('rewardManager-2'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-2')), 55 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-2')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-2')), 45 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-2')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 3);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 3);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-2')), 2);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-2')), 2);
  }

  function test_batch_claim_rewards_by_multiple_stakers() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    uint96[] memory validatorWeights = new uint96[](2);
    validatorWeights[0] = 50;
    validatorWeights[1] = 50;
    uint128[] memory validatorCollateralRewardShare = new uint128[](2);
    validatorCollateralRewardShare[0] = 80;
    validatorCollateralRewardShare[1] = 50;
    uint128[] memory validatorDelegationRewardShare = new uint128[](2);
    validatorDelegationRewardShare[0] = 20;
    validatorDelegationRewardShare[1] = 50;

    ValidatorParam[] memory validatorParams = new ValidatorParam[](2);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 80,
      delegationRewardShare: 20
    });
    validatorParams[1] = ValidatorParam({
      valAddr: makeAddr('val-2'),
      operatorAddr: makeAddr('operator-2'),
      rewardManager: makeAddr('rewardManager-2'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-2'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](3);
    uint256[] memory amounts = new uint256[](3);
    stakers[0] = makeAddr('staker-1');
    stakers[1] = makeAddr('staker-2');
    stakers[2] = makeAddr('staker-3');
    amounts[0] = 50;
    amounts[1] = 25;
    amounts[2] = 25;

    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    validatorParams[1].stakers = stakers;
    validatorParams[1].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 41 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 4.5 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-2'), makeAddr('val-1'));
    assertEq(claimable, 2.25 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-3'), makeAddr('val-1'));
    assertEq(claimable, 2.25 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 27.5 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 11.25 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-2'), makeAddr('val-2'));
    assertEq(claimable, 5.625 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-3'), makeAddr('val-2'));
    assertEq(claimable, 5.625 ether);
    assertEq(nextEpoch, 2);

    address[] memory valAddrs = new address[](2);
    valAddrs[0] = makeAddr('val-1');
    valAddrs[1] = makeAddr('val-2');

    // approve operator claim
    address operatorBatchClaimer = makeAddr('operatorBatchClaimer');
    vm.prank(makeAddr('rewardManager-1'));
    _distributor.setOperatorClaimApprovalStatus(valAddrs[0], operatorBatchClaimer, true);
    vm.prank(makeAddr('rewardManager-2'));
    _distributor.setOperatorClaimApprovalStatus(valAddrs[1], operatorBatchClaimer, true);

    vm.prank(makeAddr('operatorBatchClaimer'));
    assertEq(_distributor.batchClaimOperatorRewards(valAddrs), 41 ether + 27.5 ether);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-2')), 1);

    address[][] memory valAddrsArr = new address[][](3);
    valAddrsArr[0] = valAddrs;
    valAddrsArr[1] = valAddrs;
    valAddrsArr[2] = valAddrs;

    // approve staker claim
    address stakerBatchClaimer = makeAddr('stakerBatchClaimer');

    vm.startPrank(makeAddr('staker-1'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[0], stakerBatchClaimer, true);
    _distributor.setStakerClaimApprovalStatus(valAddrs[1], stakerBatchClaimer, true);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-2'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[0], stakerBatchClaimer, true);
    _distributor.setStakerClaimApprovalStatus(valAddrs[1], stakerBatchClaimer, true);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-3'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[0], stakerBatchClaimer, true);
    _distributor.setStakerClaimApprovalStatus(valAddrs[1], stakerBatchClaimer, true);
    vm.stopPrank();

    vm.prank(stakerBatchClaimer);
    assertEq(_distributor.batchClaimStakerRewards(stakers, valAddrsArr), 31.5 ether);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-2'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-3'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-2'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-3'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-2'), makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-3'), makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-2')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-2'), makeAddr('val-2')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-3'), makeAddr('val-2')), 1);
  }

  function test_claim_rewards_validator_collateral_zero() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 0,
      delegationRewardShare: 100
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 0, stakers: 100, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 10 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 90 ether);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 10 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 90 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
  }

  function test_claim_rewards_validator_delegation_zero() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 100,
      delegationRewardShare: 0
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 0, stakers: 100, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 100 ether);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 100 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.prank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
  }

  function test_claim_rewards_unavailable() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: false,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);

    vm.prank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.prank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 0);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 0);
  }

  function test_claim_batch_rewards_unavailable() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: false,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](2);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    validatorParams[1] = ValidatorParam({
      valAddr: makeAddr('val-2'),
      operatorAddr: makeAddr('operator-2'),
      rewardManager: makeAddr('rewardManager-2'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-2'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });

    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    validatorParams[1].stakers = stakers;
    validatorParams[1].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);

    address[] memory valAddrs = new address[](2);
    valAddrs[0] = makeAddr('val-1');
    valAddrs[1] = makeAddr('val-2');

    address operatorBatchClaimer = makeAddr('operatorBatchClaimer');
    vm.prank(makeAddr('rewardManager-1'));
    _distributor.setOperatorClaimApprovalStatus(valAddrs[0], operatorBatchClaimer, true);
    vm.prank(makeAddr('rewardManager-2'));
    _distributor.setOperatorClaimApprovalStatus(valAddrs[1], operatorBatchClaimer, true);

    vm.prank(operatorBatchClaimer);
    assertEq(_distributor.batchClaimOperatorRewards(valAddrs), 0);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 0);
    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-2')), 0);

    address[][] memory valAddrsArr = new address[][](1);
    valAddrsArr[0] = valAddrs;

    address stakerBatchClaimer = makeAddr('stakerBatchClaimer');
    vm.startPrank(makeAddr('staker-1'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[0], stakerBatchClaimer, true);
    _distributor.setStakerClaimApprovalStatus(valAddrs[1], stakerBatchClaimer, true);
    vm.stopPrank();

    vm.prank(stakerBatchClaimer);
    assertEq(_distributor.batchClaimStakerRewards(stakers, valAddrsArr), 0);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-2'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 1);

    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 0);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-2')), 0);
  }

  function test_claim_rewards_gt_32_epochs() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    uint256 epochCount = 35;

    EpochParam[] memory epochParams = new EpochParam[](epochCount);

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);
    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    for (uint256 i = 0; i < epochCount; i++) {
      epochParams[i] = EpochParam({
        epoch: i + 1,
        startsAt: 100 * (i + 1),
        endsAt: 100 * (i + 1) + 100,
        available: true,
        totalReward: 100 ether,
        validatorParams: validatorParams
      });
    }

    _setUpEpochs(epochParams);

    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 1760 ether);
    assertEq(nextEpoch, 33);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 1440 ether);
    assertEq(nextEpoch, 33);

    vm.prank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 1760 ether);

    vm.prank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 1440 ether);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 32);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 32);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 165 ether);
    assertEq(nextEpoch, 36);
    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 135 ether);
    assertEq(nextEpoch, 36);

    vm.prank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 165 ether);

    vm.prank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 135 ether);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 35);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 35);
  }

  function test_claim_approval_own() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 50, stakers: 50, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 55 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 45 ether);
    assertEq(nextEpoch, 2);

    // The rewardManager and staker are inherently eligible to claim.
    vm.startPrank(makeAddr('rewardManager-1'));
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 55 ether);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 0);
    vm.stopPrank();

    vm.startPrank(makeAddr('staker-1'));
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 45 ether);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 0);
    vm.stopPrank();

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
  }

  function test_claim_approval_delegate() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 50, stakers: 50, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 55 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 45 ether);
    assertEq(nextEpoch, 2);

    address claimer = makeAddr('claimer');

    // operator

    vm.expectRevert(_errUnauthorized());
    vm.prank(claimer);
    _distributor.claimOperatorRewards(makeAddr('val-1'));

    vm.prank(makeAddr('rewardManager-1'));
    _distributor.setOperatorClaimApprovalStatus(makeAddr('val-1'), claimer, true);

    vm.prank(claimer);
    assertEq(_distributor.claimOperatorRewards(makeAddr('val-1')), 55 ether);

    // staker

    vm.expectRevert(_errUnauthorized());
    vm.prank(claimer);
    _distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));

    vm.prank(makeAddr('staker-1'));
    _distributor.setStakerClaimApprovalStatus(makeAddr('val-1'), claimer, true);

    vm.prank(claimer);
    assertEq(_distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1')), 45 ether);

    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 0);
    assertEq(nextEpoch, 2);

    assertEq(_distributor.lastClaimedOperatorRewardsEpoch(makeAddr('val-1')), 1);
    assertEq(_distributor.lastClaimedStakerRewardsEpoch(makeAddr('staker-1'), makeAddr('val-1')), 1);
  }

  function test_claim_approval_false() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    ValidatorParam[] memory validatorParams = new ValidatorParam[](1);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 100,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    stakers[0] = makeAddr('staker-1');
    amounts[0] = 100;
    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    // operator: 50, stakers: 50, commission: 10%
    uint256 claimable;
    uint256 nextEpoch;
    (claimable, nextEpoch) = _distributor.claimableOperatorRewards(makeAddr('val-1'));
    assertEq(claimable, 55 ether);
    assertEq(nextEpoch, 2);

    (claimable, nextEpoch) = _distributor.claimableStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
    assertEq(claimable, 45 ether);
    assertEq(nextEpoch, 2);

    address claimer = makeAddr('claimer');

    // operator

    vm.expectRevert(_errUnauthorized());
    vm.prank(claimer);
    _distributor.claimOperatorRewards(makeAddr('val-1'));

    vm.prank(makeAddr('rewardManager-1'));
    _distributor.setOperatorClaimApprovalStatus(makeAddr('val-1'), claimer, true);

    vm.prank(makeAddr('rewardManager-1'));
    _distributor.setOperatorClaimApprovalStatus(makeAddr('val-1'), claimer, false);

    vm.expectRevert(_errUnauthorized());
    vm.prank(claimer);
    _distributor.claimOperatorRewards(makeAddr('val-1'));

    // staker

    vm.expectRevert(_errUnauthorized());
    vm.prank(claimer);
    _distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));

    vm.prank(makeAddr('staker-1'));
    _distributor.setStakerClaimApprovalStatus(makeAddr('val-1'), claimer, true);

    vm.prank(makeAddr('staker-1'));
    _distributor.setStakerClaimApprovalStatus(makeAddr('val-1'), claimer, false);

    vm.expectRevert(_errUnauthorized());
    vm.prank(claimer);
    _distributor.claimStakerRewards(makeAddr('staker-1'), makeAddr('val-1'));
  }

  function test_batch_claim_approval() public {
    require(vm.revertToState(snapshotId), 'Failed to initialize');

    EpochParam[] memory epochParams = new EpochParam[](1);
    epochParams[0] = EpochParam({
      epoch: 1,
      startsAt: 100,
      endsAt: 200,
      available: true,
      totalReward: 100 ether,
      validatorParams: new ValidatorParam[](0) // init
     });

    uint96[] memory validatorWeights = new uint96[](2);
    validatorWeights[0] = 50;
    validatorWeights[1] = 50;
    uint128[] memory validatorCollateralRewardShare = new uint128[](2);
    validatorCollateralRewardShare[0] = 80;
    validatorCollateralRewardShare[1] = 50;
    uint128[] memory validatorDelegationRewardShare = new uint128[](2);
    validatorDelegationRewardShare[0] = 20;
    validatorDelegationRewardShare[1] = 50;

    ValidatorParam[] memory validatorParams = new ValidatorParam[](2);

    validatorParams[0] = ValidatorParam({
      valAddr: makeAddr('val-1'),
      operatorAddr: makeAddr('operator-1'),
      rewardManager: makeAddr('rewardManager-1'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-1'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 80,
      delegationRewardShare: 20
    });
    validatorParams[1] = ValidatorParam({
      valAddr: makeAddr('val-2'),
      operatorAddr: makeAddr('operator-2'),
      rewardManager: makeAddr('rewardManager-2'),
      withdrawalRecipient: makeAddr('withdrawalRecipient-2'),
      commissionRate: 1000,
      stakers: new address[](0), // init
      amounts: new uint256[](0), // init
      weight: 50,
      collateralRewardShare: 50,
      delegationRewardShare: 50
    });
    address[] memory stakers = new address[](3);
    uint256[] memory amounts = new uint256[](3);
    stakers[0] = makeAddr('staker-1');
    stakers[1] = makeAddr('staker-2');
    stakers[2] = makeAddr('staker-3');
    amounts[0] = 50;
    amounts[1] = 25;
    amounts[2] = 25;

    validatorParams[0].stakers = stakers;
    validatorParams[0].amounts = amounts;

    validatorParams[1].stakers = stakers;
    validatorParams[1].amounts = amounts;

    epochParams[0].validatorParams = validatorParams;

    _setUpEpochs(epochParams);

    address[] memory valAddrs = new address[](2);
    valAddrs[0] = makeAddr('val-1');
    valAddrs[1] = makeAddr('val-2');

    // approve operator batch claim

    address operatorBatchClaimer = makeAddr('operatorBatchClaimer');

    vm.expectRevert(_errUnauthorized());
    vm.prank(makeAddr('operatorBatchClaimer'));
    _distributor.batchClaimOperatorRewards(valAddrs);

    vm.prank(makeAddr('rewardManager-1'));
    _distributor.setOperatorClaimApprovalStatus(valAddrs[0], operatorBatchClaimer, true);

    vm.expectRevert(_errUnauthorized());
    vm.prank(makeAddr('operatorBatchClaimer'));
    _distributor.batchClaimOperatorRewards(valAddrs);

    vm.prank(makeAddr('rewardManager-2'));
    _distributor.setOperatorClaimApprovalStatus(valAddrs[1], operatorBatchClaimer, true);

    vm.prank(makeAddr('operatorBatchClaimer'));
    assertEq(_distributor.batchClaimOperatorRewards(valAddrs), 41 ether + 27.5 ether);

    // approve staker batch claim

    address[][] memory valAddrsArr = new address[][](3);
    valAddrsArr[0] = valAddrs;
    valAddrsArr[1] = valAddrs;
    valAddrsArr[2] = valAddrs;

    address stakerBatchClaimer = makeAddr('stakerBatchClaimer');

    vm.expectRevert(_errUnauthorized());
    vm.prank(stakerBatchClaimer);
    _distributor.batchClaimStakerRewards(stakers, valAddrsArr);

    vm.prank(makeAddr('staker-1'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[0], stakerBatchClaimer, true);

    vm.expectRevert(_errUnauthorized());
    vm.prank(stakerBatchClaimer);
    _distributor.batchClaimStakerRewards(stakers, valAddrsArr);

    vm.prank(makeAddr('staker-1'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[1], stakerBatchClaimer, true);

    vm.expectRevert(_errUnauthorized());
    vm.prank(stakerBatchClaimer);
    _distributor.batchClaimStakerRewards(stakers, valAddrsArr);

    vm.prank(makeAddr('staker-2'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[0], stakerBatchClaimer, true);

    vm.expectRevert(_errUnauthorized());
    vm.prank(stakerBatchClaimer);
    _distributor.batchClaimStakerRewards(stakers, valAddrsArr);

    vm.prank(makeAddr('staker-2'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[1], stakerBatchClaimer, true);

    vm.expectRevert(_errUnauthorized());
    vm.prank(stakerBatchClaimer);
    _distributor.batchClaimStakerRewards(stakers, valAddrsArr);

    vm.prank(makeAddr('staker-3'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[0], stakerBatchClaimer, true);

    vm.expectRevert(_errUnauthorized());
    vm.prank(stakerBatchClaimer);
    _distributor.batchClaimStakerRewards(stakers, valAddrsArr);

    vm.prank(makeAddr('staker-3'));
    _distributor.setStakerClaimApprovalStatus(valAddrs[1], stakerBatchClaimer, true);

    vm.prank(stakerBatchClaimer);
    assertEq(_distributor.batchClaimStakerRewards(stakers, valAddrsArr), 31.5 ether);
  }

  function test_setOperatorClaimApprovalStatus() public {
    address valAddr = makeAddr('val-1');
    address rewardManager = makeAddr('rewardManager-1');
    address claimer = makeAddr('claimer');

    assertEq(_distributor.operatorClaimAllowed(rewardManager, valAddr, rewardManager), true);

    assertEq(_distributor.operatorClaimAllowed(rewardManager, valAddr, claimer), false);

    vm.prank(rewardManager);
    _distributor.setOperatorClaimApprovalStatus(valAddr, claimer, true);

    assertEq(_distributor.operatorClaimAllowed(rewardManager, valAddr, claimer), true);

    vm.prank(rewardManager);
    _distributor.setOperatorClaimApprovalStatus(valAddr, claimer, false);

    assertEq(_distributor.operatorClaimAllowed(rewardManager, valAddr, claimer), false);
  }

  function test_setStakerClaimApprovalStatus() public {
    address valAddr = makeAddr('val-1');
    address staker = makeAddr('staker-1');
    address claimer = makeAddr('claimer');

    assertEq(_distributor.stakerClaimAllowed(staker, valAddr, staker), true);

    assertEq(_distributor.stakerClaimAllowed(staker, valAddr, claimer), false);

    vm.prank(staker);
    _distributor.setStakerClaimApprovalStatus(valAddr, claimer, true);

    assertEq(_distributor.stakerClaimAllowed(staker, valAddr, claimer), true);

    vm.prank(staker);
    _distributor.setStakerClaimApprovalStatus(valAddr, claimer, false);

    assertEq(_distributor.stakerClaimAllowed(staker, valAddr, claimer), false);
  }

  function _setUpEpochs(EpochParam[] memory params) internal {
    _validatorManager.setRet(abi.encodeCall(IValidatorManager.MAX_COMMISSION_RATE, ()), false, abi.encode(10000));

    for (uint256 i = 0; i < params.length; i++) {
      // ========== epoch setup ==========
      EpochParam memory epochParam = params[i];

      // For amount calculating
      vm.warp(epochParam.startsAt);

      _epochFeed.setRet(abi.encodeCall(IEpochFeeder.timeAt, (epochParam.epoch)), false, abi.encode(epochParam.startsAt));

      _contributionFeed.setRet(
        abi.encodeCall(IValidatorContributionFeed.available, (epochParam.epoch)),
        false,
        abi.encode(epochParam.available)
      );

      _govMITOEmission.setRet(
        abi.encodeCall(IGovMITOEmission.validatorReward, (epochParam.epoch)), false, abi.encode(epochParam.totalReward)
      );

      // ========== validator setup ==========
      uint128 totalWeight = 0;
      for (uint256 j = 0; j < epochParam.validatorParams.length; j++) {
        ValidatorParam memory validatorParam = epochParam.validatorParams[j];

        IValidatorManager.ValidatorInfoResponse memory validatorInfoResponse = IValidatorManager.ValidatorInfoResponse(
          validatorParam.valAddr, // address valAddr;
          '', // bytes valKey;
          validatorParam.operatorAddr, // address operator;
          validatorParam.rewardManager, // address rewardManager;
          validatorParam.withdrawalRecipient, // withdrawalRecipient
          validatorParam.commissionRate, // uint256 commissionRate;
          bytes('') // bytes metadata;
        );

        _validatorManager.setRet(
          abi.encodeCall(IValidatorManager.validatorInfo, (validatorParam.valAddr)),
          false,
          abi.encode(validatorInfoResponse)
        );
        _validatorManager.setRet(
          abi.encodeCall(IValidatorManager.validatorInfoAt, (epochParam.epoch, validatorParam.valAddr)),
          false,
          abi.encode(validatorInfoResponse)
        );
        _contributionFeed.setRet(
          abi.encodeCall(IValidatorContributionFeed.weightOf, (epochParam.epoch, validatorParam.valAddr)),
          false,
          abi.encode(
            IValidatorContributionFeed.ValidatorWeight(
              validatorParam.valAddr, // address addr;
              validatorParam.weight, // uint96 weight; // max 79 billion * 1e18
              validatorParam.collateralRewardShare, // uint128 collateralRewardShare;
              validatorParam.delegationRewardShare // uint128 delegationRewardShare;
            ),
            true
          )
        );
        totalWeight += validatorParam.weight;

        for (uint256 k = 0; k < validatorParam.stakers.length; k++) {
          address staker = validatorParam.stakers[k];
          uint256 amount = validatorParam.amounts[k];
          _stakingHub.notifyStake(validatorParam.valAddr, staker, amount);
        }
      }

      _contributionFeed.setRet(
        abi.encodeCall(IValidatorContributionFeed.summary, (epochParam.epoch)),
        false,
        abi.encode(
          totalWeight, // uint128 totalWeight;
          uint128(epochParam.validatorParams.length) // uint128 numOfValidators;
        )
      );
    }

    uint256 lastEpoch = params[params.length - 1].epoch + 1;
    uint256 lastEpochTime = params[params.length - 1].endsAt;
    _epochFeed.setRet(abi.encodeCall(IEpochFeeder.epoch, ()), false, abi.encode(lastEpoch));
    _epochFeed.setRet(abi.encodeCall(IEpochFeeder.timeAt, (lastEpoch)), false, abi.encode(lastEpochTime));

    _contributionFeed.setRet(
      abi.encodeCall(IValidatorContributionFeed.available, (lastEpoch)), false, abi.encode(false)
    );

    vm.warp(lastEpochTime);
  }
}
