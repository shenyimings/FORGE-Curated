// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IConvexRewardPool {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns(bool);
    function getReward(address _account, bool _claimExtras) external returns(bool);
    function balanceOf(address _account) external view returns(uint256);
    function pid() external view returns(uint256);
    function operator() external view returns(address);
    function extraRewards(uint256 idx) external view returns (address);
    function extraRewardsLength() external view returns (uint256);
}

interface IConvexBooster {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
    function stakerRewards() external view returns(address);
}

interface IConvexBoosterArbitrum {
    function deposit(uint256 _pid, uint256 _amount) external returns(bool);
}