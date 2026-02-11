// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SPRL2_ClaimRewards_Integrations_Test is Integrations_Test {
    uint256 REWARD_AMOUNT = 10e18;

    modifier addMainReward() {
        rewardToken.mint(address(sprl2), REWARD_AMOUNT);
        _;
    }

    modifier addExtraReward() {
        extraRewardToken.mint(address(sprl2), REWARD_AMOUNT);
        _;
    }

    function test_SPRL2_ClaimRewards_OnlyMainReward() external addMainReward {
        uint256 feeReceiverMainRewardBalance = rewardToken.balanceOf(users.daoTreasury.addr);
        sprl2.claimRewards();
        assertEq(rewardToken.balanceOf(address(sprl2)), 0);
        assertEq(rewardToken.balanceOf(users.daoTreasury.addr), feeReceiverMainRewardBalance + REWARD_AMOUNT);
        assertEq(extraRewardToken.balanceOf(address(sprl2)), 0);
        assertEq(extraRewardToken.balanceOf(users.daoTreasury.addr), 0);
    }

    function test_SPRL2_ClaimRewards_OnlyExtraReward() external addExtraReward {
        uint256 feeReceiverExtraRewardBalance = extraRewardToken.balanceOf(users.daoTreasury.addr);
        sprl2.claimRewards();
        assertEq(rewardToken.balanceOf(address(sprl2)), 0);
        assertEq(rewardToken.balanceOf(users.daoTreasury.addr), 0);
        assertEq(extraRewardToken.balanceOf(address(sprl2)), 0);
        assertEq(extraRewardToken.balanceOf(users.daoTreasury.addr), feeReceiverExtraRewardBalance + REWARD_AMOUNT);
    }

    function test_SPRL2_ClaimRewards_BothRewards() external addMainReward addExtraReward {
        uint256 feeReceiverMainRewardBalance = rewardToken.balanceOf(users.daoTreasury.addr);
        uint256 feeReceiverExtraRewardBalance = extraRewardToken.balanceOf(users.daoTreasury.addr);
        sprl2.claimRewards();
        assertEq(rewardToken.balanceOf(address(sprl2)), 0);
        assertEq(rewardToken.balanceOf(users.daoTreasury.addr), feeReceiverMainRewardBalance + REWARD_AMOUNT);
        assertEq(extraRewardToken.balanceOf(address(sprl2)), 0);
        assertEq(extraRewardToken.balanceOf(users.daoTreasury.addr), feeReceiverExtraRewardBalance + REWARD_AMOUNT);
    }
}
