// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractRewardManager, RewardPoolStorage} from "./AbstractRewardManager.sol";
import {IConvexRewardPool, IConvexBooster} from "../interfaces/Curve/IConvex.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";

contract ConvexRewardManager is AbstractRewardManager {
    using TokenUtils for ERC20;

    function _executeClaim() internal override {
        address rewardPool = _getRewardPoolSlot().rewardPool;
        require(IConvexRewardPool(rewardPool).getReward(address(this), true));
    }

    function _withdrawFromPreviousRewardPool(RewardPoolStorage memory oldRewardPool) internal override {
        uint256 boosterBalance = ERC20(oldRewardPool.rewardPool).balanceOf(address(this));
        require(IConvexRewardPool(oldRewardPool.rewardPool).withdrawAndUnwrap(boosterBalance, true));
    }

    function _depositIntoNewRewardPool(address poolToken, uint256 poolTokens, RewardPoolStorage memory newRewardPool) internal override {
        uint256 poolId = IConvexRewardPool(newRewardPool.rewardPool).pid();
        address booster = IConvexRewardPool(newRewardPool.rewardPool).operator();
        ERC20(poolToken).checkApprove(booster, type(uint256).max);

        if (poolTokens > 0) {
            require(IConvexBooster(booster).deposit(poolId, poolTokens, true));
        }
    }
}
