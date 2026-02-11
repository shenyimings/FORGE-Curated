// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IEpochFeeder } from './IEpochFeeder.sol';

interface IValidatorContributionFeed {
  struct ValidatorWeight {
    address addr;
    uint96 weight; // max 79 billion * 1e18
    uint128 collateralRewardShare;
    uint128 delegationRewardShare;
  }

  enum ReportStatus {
    NONE,
    INITIALIZED,
    REVOKING,
    FINALIZED
  }

  struct ReportRequest {
    uint128 totalWeight;
    ValidatorWeight[] weights;
  }

  struct InitReportRequest {
    uint128 totalWeight;
    uint16 numOfValidators;
  }

  struct Summary {
    uint128 totalWeight;
    uint128 numOfValidators;
  }

  event ReportInitialized(uint256 epoch, uint128 totalWeight, uint128 numOfValidators);
  event WeightsPushed(uint256 epoch, uint128 totalWeight, uint128 numOfValidators);
  event ReportFinalized(uint256 epoch);
  event ReportRevoking(uint256 epoch);
  event ReportRevoked(uint256 epoch);

  error IValidatorContributionFeed__InvalidReportStatus();
  error IValidatorContributionFeed__InvalidWeightAddress();
  error IValidatorContributionFeed__InvalidWeightCount();
  error IValidatorContributionFeed__InvalidTotalWeight();
  error IValidatorContributionFeed__InvalidValidatorCount();
  error IValidatorContributionFeed__ReportNotReady();

  function epochFeeder() external view returns (IEpochFeeder);

  function weightCount(uint256 epoch) external view returns (uint256);

  function weightAt(uint256 epoch, uint256 index) external view returns (ValidatorWeight memory);

  function weightOf(uint256 epoch, address valAddr) external view returns (ValidatorWeight memory, bool);

  function available(uint256 epoch) external view returns (bool);

  function summary(uint256 epoch) external view returns (Summary memory);

  function initializeReport(InitReportRequest calldata request) external;

  function pushValidatorWeights(ValidatorWeight[] calldata weights) external;

  function finalizeReport() external;

  function revokeReport() external;
}
