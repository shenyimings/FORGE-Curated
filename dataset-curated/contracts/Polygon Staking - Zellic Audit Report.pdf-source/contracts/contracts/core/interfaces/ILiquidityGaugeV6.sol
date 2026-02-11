// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface ILiquidityGaugeV6 {
    function deposit_reward_token(address _rewardToken, uint256 _amount, uint256 _epoch) external;
}
