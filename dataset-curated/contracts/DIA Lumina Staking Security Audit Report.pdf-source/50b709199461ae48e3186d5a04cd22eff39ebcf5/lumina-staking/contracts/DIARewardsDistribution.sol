// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title DIARewardsDistribution
 * @notice Abstract contract for managing token rewards distribution
 * @dev Provides base functionality for reward rate and wallet management
 */
abstract contract DIARewardsDistribution is Ownable {
    /// @notice The ERC20 token used for rewards
    IERC20 public immutable REWARDS_TOKEN;

    // Reward rate per day, with 10 decimals
    uint256 public rewardRatePerDay;

    /// @notice Address of the wallet that holds rewards
    /// @dev This wallet must approve tokens for the staking contract
    address public rewardsWallet;

    /// @notice Error thrown when an invalid address is provided
    error InvalidAddress();

    /// @notice Emitted when reward rate is updated
    /// @param oldRewardRate The previous reward rate
    /// @param newRewardRate The new reward rate
    event RewardRateUpdated(uint256 oldRewardRate, uint256 newRewardRate);

    /// @notice Emitted when rewards wallet is updated
    /// @param oldWallet The previous rewards wallet address
    /// @param newWallet The new rewards wallet address
    event RewardsWalletUpdated(address oldWallet, address newWallet);

    /**
     * @notice Initializes the contract with reward parameters
     * @param rewardsTokenAddress Address of the ERC20 token used for rewards
     * @param newRewardsWallet Address of the wallet that holds rewards
     * @param newRewardRate Initial reward rate per day
     */
    constructor(
        address rewardsTokenAddress,
        address newRewardsWallet,
        uint256 newRewardRate
    ) {
        REWARDS_TOKEN = IERC20(rewardsTokenAddress);
        rewardRatePerDay = newRewardRate;
        rewardsWallet = newRewardsWallet;
    }

    /**
     * @notice Updates the daily reward rate
     * @dev Only callable by the contract owner
     * @param newRewardRate The new reward rate per day
     * @custom:event Emits RewardRateUpdated with old and new values
     */
    function updateRewardRatePerDay(uint256 newRewardRate) external onlyOwner {
        emit RewardRateUpdated(rewardRatePerDay, newRewardRate);
        rewardRatePerDay = newRewardRate;
    }

    /**
     * @notice Updates the rewards wallet address
     * @dev Only callable by the contract owner
     * @param newWalletAddress The new rewards wallet address
     * @custom:revert InvalidAddress if new wallet address is zero
     * @custom:event Emits RewardsWalletUpdated with old and new values
     */
    function updateRewardsWallet(address newWalletAddress) external onlyOwner {
        if (newWalletAddress == address(0)) {
            revert InvalidAddress();
        }
        emit RewardsWalletUpdated(rewardsWallet, newWalletAddress);
        rewardsWallet = newWalletAddress;
    }

    /**
     * @notice Calculates the reward for a given staking store
     * @dev Must be implemented by inheriting contracts
     * @param stakingStoreIndex The index of the staking store
     * @return The calculated reward amount
     */
    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public virtual returns (uint256);
}
