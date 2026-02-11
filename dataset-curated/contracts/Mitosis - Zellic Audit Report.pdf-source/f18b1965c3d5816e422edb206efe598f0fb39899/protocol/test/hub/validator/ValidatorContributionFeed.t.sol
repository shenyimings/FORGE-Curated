// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';

import { LibClone } from '@solady/utils/LibClone.sol';
import { LibString } from '@solady/utils/LibString.sol';

import { ValidatorContributionFeed } from '../../../src/hub/validator/ValidatorContributionFeed.sol';
import { IEpochFeeder } from '../../../src/interfaces/hub/validator/IEpochFeeder.sol';
import { IValidatorContributionFeed } from '../../../src/interfaces/hub/validator/IValidatorContributionFeed.sol';
import { StdError } from '../../../src/lib/StdError.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract ValidatorContributionFeedTest is Toolkit {
  using SafeCast for uint256;
  using LibString for *;

  address owner = makeAddr('owner');
  address feeder = makeAddr('feeder');
  address abuser = makeAddr('abuser');

  MockContract epochFeeder;
  ValidatorContributionFeed feed;

  function setUp() public {
    epochFeeder = new MockContract();

    feed = ValidatorContributionFeed(
      address(
        new ERC1967Proxy(
          address(new ValidatorContributionFeed(IEpochFeeder(address(epochFeeder)))),
          abi.encodeCall(ValidatorContributionFeed.initialize, (owner))
        )
      )
    );

    vm.startPrank(owner);
    feed.grantRole(feed.FEEDER_ROLE(), feeder);
    vm.stopPrank();
  }

  function test_init() public view {
    assertEq(feed.owner(), owner);
    assertEq(address(feed.epochFeeder()), address(epochFeeder));
    assertEq(feed.FEEDER_ROLE(), keccak256('mitosis.role.ValidatorContributionFeed.feeder'));
  }

  function test_report() public {
    _mockEpoch(2);

    bytes32 feederRole = feed.FEEDER_ROLE();

    vm.prank(abuser);
    vm.expectRevert(_errAccessControlUnauthorized(abuser, feederRole));
    feed.initializeReport(IValidatorContributionFeed.InitReportRequest({ totalWeight: 300e18, numOfValidators: 300 }));

    vm.prank(feeder);
    vm.expectEmit();
    emit IValidatorContributionFeed.ReportInitialized(1, 300e18, 300);
    feed.initializeReport(IValidatorContributionFeed.InitReportRequest({ totalWeight: 300e18, numOfValidators: 300 }));

    for (uint256 i = 0; i < 6; i++) {
      IValidatorContributionFeed.ValidatorWeight[] memory weights = _makeValidatorWeights(50);
      for (uint256 j = 0; j < 50; j++) {
        address addr = makeAddr(string.concat('val-', ((i * 50) + j).toString()));
        weights[j] = _makeValidatorWeight(addr, 1e18, 1e18, 1e18);
      }

      vm.prank(abuser);
      vm.expectRevert(_errAccessControlUnauthorized(abuser, feederRole));
      feed.pushValidatorWeights(weights);

      vm.prank(feeder);
      vm.expectEmit();
      emit IValidatorContributionFeed.WeightsPushed(1, 50e18, 50);
      feed.pushValidatorWeights(weights);
    }

    vm.prank(abuser);
    vm.expectRevert(_errAccessControlUnauthorized(abuser, feederRole));
    feed.finalizeReport();

    vm.prank(feeder);
    vm.expectEmit();
    emit IValidatorContributionFeed.ReportFinalized(1);
    feed.finalizeReport();

    // check weight query
    assertEq(feed.weightCount(1), 300);
    for (uint256 i = 0; i < 6; i++) {
      for (uint256 j = 0; j < 50; j++) {
        address addr = makeAddr(string.concat('val-', ((i * 50) + j).toString()));
        assertTrue(_eq(feed.weightAt(1, (i * 50) + j), _makeValidatorWeight(addr, 1e18, 1e18, 1e18)));

        (IValidatorContributionFeed.ValidatorWeight memory w, bool exists) = feed.weightOf(1, addr);
        assertTrue(exists);
        assertTrue(_eq(w, _makeValidatorWeight(addr, 1e18, 1e18, 1e18)));
      }
    }

    // check weight query for non-existent weight
    {
      (IValidatorContributionFeed.ValidatorWeight memory w, bool exists) = feed.weightOf(1, makeAddr('random'));
      assertFalse(exists);
      assertTrue(_eq(w, _makeValidatorWeight(address(0), 0, 0, 0)));
    }

    // check report availability
    assertTrue(feed.available(1));
    assertFalse(feed.available(2));

    // check report summary
    assertEq(feed.summary(1).totalWeight, 300e18);
    assertEq(feed.summary(1).numOfValidators, 300);
  }

  function test_finalizeReport_InvalidReportStatus() public {
    _mockEpoch(2);

    vm.prank(feeder);
    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__InvalidReportStatus.selector);
    feed.finalizeReport();
  }

  function test_finalizeReport_InvalidTotalWeight() public {
    _mockEpoch(2);

    vm.prank(feeder);
    feed.initializeReport(IValidatorContributionFeed.InitReportRequest({ totalWeight: 300e18, numOfValidators: 300 }));

    for (uint256 i = 0; i < 6; i++) {
      IValidatorContributionFeed.ValidatorWeight[] memory weights = _makeValidatorWeights(50);
      for (uint256 j = 0; j < 50; j++) {
        address addr = makeAddr(string.concat('val-', ((i * 50) + j).toString()));
        weights[j] = _makeValidatorWeight(addr, 2e18, 1e18, 1e18);
      }

      vm.prank(feeder);
      feed.pushValidatorWeights(weights);
    }

    vm.prank(feeder);
    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__InvalidTotalWeight.selector);
    feed.finalizeReport();
  }

  function test_finalizeReport_InvalidValidatorCount() public {
    _mockEpoch(2);

    vm.prank(feeder);
    feed.initializeReport(IValidatorContributionFeed.InitReportRequest({ totalWeight: 300e18, numOfValidators: 300 }));

    for (uint256 i = 0; i < 10; i++) {
      IValidatorContributionFeed.ValidatorWeight[] memory weights = _makeValidatorWeights(50);
      for (uint256 j = 0; j < 50; j++) {
        address addr = makeAddr(string.concat('val-', ((i * 50) + j).toString()));
        weights[j] = _makeValidatorWeight(addr, 0.6e18, 1e18, 1e18);
      }

      vm.prank(feeder);
      feed.pushValidatorWeights(weights);
    }

    vm.prank(feeder);
    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__InvalidValidatorCount.selector);
    feed.finalizeReport();
  }

  function test_revokeReport() public {
    _mockEpoch(2);

    vm.prank(feeder);
    feed.initializeReport(IValidatorContributionFeed.InitReportRequest({ totalWeight: 300e18, numOfValidators: 300 }));

    // Push 500 validators (5 batches of 100)
    for (uint256 i = 0; i < 19; i++) {
      IValidatorContributionFeed.ValidatorWeight[] memory weights = _makeValidatorWeights(100);
      for (uint256 j = 0; j < 100; j++) {
        address addr = makeAddr(string.concat('val-', ((i * 100) + j).toString()));
        weights[j] = _makeValidatorWeight(addr, 0.6e18, 1e18, 1e18);
      }

      vm.prank(feeder);
      feed.pushValidatorWeights(weights);
    }

    // First revoke call should emit ReportRevoking event
    vm.prank(feeder);
    vm.expectEmit();
    emit IValidatorContributionFeed.ReportRevoking(1);
    feed.revokeReport();

    // Second revoke call should emit ReportRevoked event
    vm.prank(feeder);
    vm.expectEmit();
    emit IValidatorContributionFeed.ReportRevoked(1);
    feed.revokeReport();

    // Verify the report is completely removed
    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__ReportNotReady.selector);
    feed.weightCount(1);
  }

  function test_revokeReport_InvalidReportStatus() public {
    _mockEpoch(2);

    vm.prank(feeder);
    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__InvalidReportStatus.selector);
    feed.revokeReport();
  }

  function test_revokeReport_NotFeeder() public {
    _mockEpoch(2);

    vm.prank(feeder);
    feed.initializeReport(IValidatorContributionFeed.InitReportRequest({ totalWeight: 300e18, numOfValidators: 300 }));

    bytes32 role = feed.FEEDER_ROLE();
    vm.prank(abuser);
    vm.expectRevert(_errAccessControlUnauthorized(abuser, role));
    feed.revokeReport();
  }

  function test_assertReportReady() public {
    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__ReportNotReady.selector);
    feed.weightCount(1);

    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__ReportNotReady.selector);
    feed.weightAt(1, 0);

    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__ReportNotReady.selector);
    feed.weightOf(1, makeAddr('random'));

    vm.expectRevert(IValidatorContributionFeed.IValidatorContributionFeed__ReportNotReady.selector);
    feed.summary(1);
  }

  function _eq(IValidatorContributionFeed.ValidatorWeight memory a, IValidatorContributionFeed.ValidatorWeight memory b)
    internal
    pure
    returns (bool)
  {
    return a.addr == b.addr && a.weight == b.weight && a.collateralRewardShare == b.collateralRewardShare
      && a.delegationRewardShare == b.delegationRewardShare;
  }

  function _mockEpoch(uint256 epoch) internal {
    epochFeeder.setRet(abi.encodeCall(IEpochFeeder.epoch, ()), false, abi.encode(epoch));
  }

  function _makeValidatorWeight(
    address addr,
    uint96 weight,
    uint128 collateralRewardShare,
    uint128 delegationRewardShare
  ) internal pure returns (IValidatorContributionFeed.ValidatorWeight memory) {
    return IValidatorContributionFeed.ValidatorWeight(addr, weight, collateralRewardShare, delegationRewardShare);
  }

  function _makeValidatorWeights(uint256 size)
    internal
    pure
    returns (IValidatorContributionFeed.ValidatorWeight[] memory)
  {
    return new IValidatorContributionFeed.ValidatorWeight[](size);
  }
}
