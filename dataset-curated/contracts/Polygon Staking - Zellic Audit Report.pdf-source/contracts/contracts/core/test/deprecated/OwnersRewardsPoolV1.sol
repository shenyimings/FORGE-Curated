// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./RewardsPoolV1.sol";

/**
 * @title OwnersRewardsPool
 * @dev Handles distribution of pool owners rewards
 */
contract OwnersRewardsPoolV1 is RewardsPoolV1 {
    using SafeERC20 for IERC677;

    address public poolOwners;
    uint256 public distributedRewards;

    event RewardDistributed(address indexed sender, uint256 amountStaked, uint256 amount);

    constructor(
        address _poolOwners,
        address _rewardsToken,
        string memory _dTokenName,
        string memory _dTokenSymbol
    ) RewardsPoolV1(_poolOwners, _rewardsToken, _dTokenName, _dTokenSymbol) {
        poolOwners = _poolOwners;
    }

    /**
     * @dev withdraws a user's earned rewards
     * @param _amount amount to withdraw
     **/
    function withdraw(uint256 _amount) public virtual override {
        uint256 toWithdraw = _amount;

        if (_amount == type(uint256).max) {
            toWithdraw = balanceOf(msg.sender);
        }

        distributedRewards -= toWithdraw;
        super.withdraw(toWithdraw);
    }

    /**
     * @dev withdraws all of a user's earned rewards
     * @param _account user to withdraw for
     **/
    function withdraw(address _account) external virtual nonReentrant {
        require(msg.sender == poolOwners, "PoolOwners only");

        uint256 toWithdraw = balanceOf(_account);

        if (toWithdraw > 0) {
            _updateReward(_account);
            _burn(_account, toWithdraw);
            distributedRewards -= toWithdraw;
            rewardsToken.safeTransfer(_account, toWithdraw);
            emit Withdrawn(_account, toWithdraw);
        }
    }

    /**
     * @dev ERC677 implementation that automatically calls distributeRewards
     **/
    function onTokenTransfer(address, uint256, bytes calldata) external nonReentrant {
        require(msg.sender == address(rewardsToken), "Sender must be rewards token");
        distributeRewards();
    }

    /**
     * @dev distributes new rewards that have been deposited
     **/
    function distributeRewards() public {
        require(stakingDerivative.totalSupply() > 0, "Cannot distribute when nothing is staked");
        uint256 toDistribute = rewardsToken.balanceOf(address(this)) - distributedRewards;
        distributedRewards += toDistribute;
        _updateRewardPerToken(toDistribute);
        emit RewardDistributed(msg.sender, stakingDerivative.totalSupply(), toDistribute);
    }
}
