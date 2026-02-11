// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title YieldProxy Proxy Contract interface
/// @notice Using for other protocols proxy call, for example: PancakeSwap, StakeDAO and etc.
interface IYieldProxy {
  // LaunchPool activity struct
  struct Activity {
    uint256 startTime;
    uint256 endTime;
    uint256 rewardedTime;
    string tokenName;
  }

  function deposit(uint256 amount) external;
  function withdraw(uint256 amount) external;
  function activitiesOnGoing() external returns (bool);
  function stakeManager() external view returns (address);
}
