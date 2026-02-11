// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./RewardsPool.sol";

/**
 * @title Rewards Pool Time Based
 * @notice Handles time based reward distribution for a single asset
 */
contract RewardsPoolTimeBased is RewardsPool, Ownable {
    using SafeERC20 for IERC677;

    uint256 public epochRewardsAmount;
    uint64 public epochExpiry;
    uint64 public epochDuration;

    uint64 public timeOfLastRewardUpdate;

    uint64 public minEpochDuration;
    uint64 public maxEpochDuration;

    event DepositRewards(uint64 epochExpiry, uint256 _rewardsAmount);

    error InvalidExpiry();
    error InvalidDuration();
    error InvalidRewardsAmount();

    constructor(
        address _controller,
        address _token,
        uint64 _minEpochDuration,
        uint64 _maxEpochDuration
    ) RewardsPool(_controller, _token) {
        if (_minEpochDuration == 0 || _maxEpochDuration == 0) revert InvalidDuration();
        minEpochDuration = _minEpochDuration;
        maxEpochDuration = _maxEpochDuration;
    }

    /**
     * @notice returns an account's total withdrawable rewards (principal balance + newly earned rewards)
     * @param _account account address
     * @return account's total unclaimed rewards
     **/
    function withdrawableRewards(address _account) public view override returns (uint256) {
        return
            (controller.staked(_account) *
                (getRewardPerToken() - userRewardPerTokenPaid[_account])) /
            1e18 +
            userRewards[_account];
    }

    /**
     * @notice deposits rewards and starts a new reward epoch
     * @dev if a previous epoch is still in progress, any undistributed rewards will be added to the new epoch
     * @param _epochExpiry expiry time of epoch in seconds
     * @param _rewardsAmount amount of new rewards to be distributed over the epoch
     **/
    function depositRewards(uint64 _epochExpiry, uint256 _rewardsAmount) external onlyOwner {
        if (controller.totalStaked() == 0) revert NothingStaked();
        if (
            _epochExpiry < epochExpiry ||
            _epochExpiry < block.timestamp + minEpochDuration ||
            _epochExpiry > block.timestamp + maxEpochDuration
        ) revert InvalidExpiry();
        if (_rewardsAmount == 0) revert InvalidRewardsAmount();

        token.safeTransferFrom(msg.sender, address(this), _rewardsAmount);
        _updateRewardPerToken(0);

        uint256 remainingRewards = timeOfLastRewardUpdate >= epochExpiry
            ? 0
            : ((epochExpiry - timeOfLastRewardUpdate) * epochRewardsAmount) / epochDuration;

        totalRewards += _rewardsAmount;
        epochRewardsAmount = remainingRewards + _rewardsAmount;
        epochDuration = _epochExpiry - uint64(block.timestamp);
        epochExpiry = _epochExpiry;
        timeOfLastRewardUpdate = uint64(block.timestamp);

        emit DepositRewards(_epochExpiry, _rewardsAmount);
    }

    /**
     * @notice updates rewardPerToken and an account's principal reward balance
     * @param _account account address
     **/
    function updateReward(address _account) public override {
        _updateRewardPerToken(0);
        super.updateReward(_account);
    }

    /**
     * @notice returns the current rewards per staked token accounting for time based rewards since the last update
     * @return current reward per token
     **/
    function getRewardPerToken() public view returns (uint256) {
        uint256 totalStaked = controller.totalStaked();
        if (totalStaked == 0) return rewardPerToken;

        uint256 newRewardsTime = block.timestamp >= epochExpiry ? epochExpiry : block.timestamp;
        uint256 newRewards = timeOfLastRewardUpdate >= newRewardsTime
            ? 0
            : (newRewardsTime - timeOfLastRewardUpdate) * getLastRewardPerSecond();
        return rewardPerToken + ((newRewards * 1e18) / totalStaked);
    }

    /**
     * @notice returns the rewardPerSecond from the current or last active epoch
     * @return last active rewardPerSecond
     **/
    function getLastRewardPerSecond() public view returns (uint256) {
        return epochDuration != 0 ? epochRewardsAmount / epochDuration : 0;
    }

    /**
     * @notice sets the minimum epoch duration
     * @param _minEpochDuration min epoch duration in seconds
     **/
    function setMinEpochDuration(uint64 _minEpochDuration) external onlyOwner {
        if (_minEpochDuration == 0) revert InvalidDuration();
        minEpochDuration = _minEpochDuration;
    }

    /**
     * @notice sets the maximum epoch duration
     * @param _maxEpochDuration max epoch duration in seconds
     **/
    function setMaxEpochDuration(uint64 _maxEpochDuration) external onlyOwner {
        if (_maxEpochDuration == 0) revert InvalidDuration();
        maxEpochDuration = _maxEpochDuration;
    }

    /**
     * @notice updates rewardPerToken
     * @param _reward optional deposited reward amount
     **/
    function _updateRewardPerToken(uint256 _reward) internal override {
        if (_reward != 0) {
            uint256 totalStaked = controller.totalStaked();
            if (totalStaked == 0) revert NothingStaked();
            rewardPerToken += ((_reward * 1e18) / totalStaked);
            return;
        }

        uint256 newRewardPerToken = getRewardPerToken();
        if (newRewardPerToken != rewardPerToken) {
            timeOfLastRewardUpdate = uint64(block.timestamp);
            rewardPerToken = newRewardPerToken;
        }
    }
}
