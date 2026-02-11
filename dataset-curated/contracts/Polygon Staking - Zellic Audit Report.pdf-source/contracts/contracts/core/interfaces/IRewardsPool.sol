// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IRewardsPool {
    function updateReward(address _account) external;

    function withdraw(address _account) external;

    function distributeRewards() external;

    function withdrawableRewards(address _account) external view returns (uint256);
}
