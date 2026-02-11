// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISpectralStaking {
    function addDistribution(
        address rewardTokenA,
        address rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB
    ) external;
    function transferCalibration(address _from, address _to, uint256 amount) external;
    function stakingToken() external view returns (address);
    function addDistributionToBuffer(
        address rewardTokenA,
        address rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB) external;
}