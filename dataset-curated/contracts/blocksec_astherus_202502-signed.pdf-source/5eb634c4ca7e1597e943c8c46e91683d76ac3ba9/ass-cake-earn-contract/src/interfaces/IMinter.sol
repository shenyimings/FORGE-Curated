// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minter interface
interface IMinter {

  enum RewardsType {
    VeTokenRewards,
    VoteRewards,
    Donate
  }

  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _token,
    address _assToken,
    address _universalProxy,
    address _swapRouter,
    address _swapPool,
    uint256 _maxSwapRatio) external;

  function smartMint(uint256 _amountIn, uint256 _mintRatio, uint256 _minOut) external returns (uint256);

  function compoundRewards(RewardsType[] memory _rewardsTypes, uint256[] memory _rewards) external;

}
