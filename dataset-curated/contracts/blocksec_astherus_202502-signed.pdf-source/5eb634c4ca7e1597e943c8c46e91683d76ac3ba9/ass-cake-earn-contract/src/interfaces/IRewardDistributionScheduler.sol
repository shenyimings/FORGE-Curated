// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IMinter.sol";

/// @title RewardDistributionScheduler interface
interface IRewardDistributionScheduler {
  function initialize(
    address _admin,
    address _token,
    address _minter,
    address _manager,
    address _pauser
  ) external;

  function addRewardsSchedule(IMinter.RewardsType _rewardsType, uint256 _amount, uint256 _epochs, uint256 _startTime) external;

  function executeRewardSchedules() external;
}
