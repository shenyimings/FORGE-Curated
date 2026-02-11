// SPDX-License-Identifier: GPL

pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DIAStakingCommons.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./DIARewardsDistribution.sol";

/**
 * @title DIAWhitelistedStaking
 * @notice This contract allows whitelisted addresses to stake tokens and earn rewards.
 */
contract DIAWhitelistedStaking is
    Ownable,
    DIARewardsDistribution,
    ReentrancyGuard,
    DIAStakingCommons
{
    using SafeERC20 for IERC20;

    /// @notice Mapping of whitelisted addresses for staking
    /// @dev Maps address to boolean indicating if address is whitelisted
    mapping(address => bool) public stakingWhitelist;

    /// @notice Emitted when a new staker is added to the whitelist
    /// @param newStaker The address that was added to the whitelist
    event StakerAddressAdded(address newStaker);

    /// @notice Emitted when a staker is removed from the whitelist
    /// @param removedStaker The address that was removed from the whitelist
    event StakerAddressRemoved(address removedStaker);

    /// @notice Emitted when daily withdrawal threshold is updated
    /// @param oldThreshold The previous threshold value
    /// @param newThreshold The new threshold value
    event DailyWithdrawalThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    );

    /// @notice Emitted when withdrawal cap is updated
    /// @param oldCap The previous cap value in basis points
    /// @param newCap The new cap value in basis points
    event WithdrawalCapUpdated(uint256 oldCap, uint256 newCap);

    /// @notice Errors
    error AlreadyWhitelisted();

    /**
     * @dev Initializes the contract with staking parameters.
     * @param newUnstakingDuration Duration in seconds required before unstaking.
     * @param stakingTokenAddress Address of the ERC20 token used for staking.
     * @param rewardsWallet Address of the wallet that holds rewards.This wallet should appove tokens for this contract
     * @param rewardRatePerDay Rate at which rewards accumulate daily.
     */

    constructor(
        uint256 newUnstakingDuration,
        address stakingTokenAddress,
        address rewardsWallet,
        uint256 rewardRatePerDay
    )
        Ownable(msg.sender)
        DIARewardsDistribution(
            stakingTokenAddress,
            rewardsWallet,
            rewardRatePerDay
        )
    {
        unstakingDuration = newUnstakingDuration;
        STAKING_TOKEN = IERC20(stakingTokenAddress);
    }

    /**
     * @notice Stakes tokens on behalf of a given address
     * @param beneficiaryAddress Address receiving the staking rewards
     * @param amount Amount of tokens to be staked
     * @param principalWalletShareBps Share of rewards going to principal wallet in basis points
     * @custom:revert NotWhitelisted if beneficiary is not whitelisted
     */
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps
    ) public nonReentrant {
        if (!stakingWhitelist[beneficiaryAddress]) {
            revert NotWhitelisted();
        }

        _internalStakeForAddress(
            msg.sender,
            beneficiaryAddress,
            amount,
            principalWalletShareBps
        );
    }

    /**
     * @notice Allows a user to stake tokens directly
     * @param amount The amount of tokens to stake
     * @custom:revert NotWhitelisted if caller is not whitelisted
     */
    function stake(uint256 amount) external nonReentrant {
        if (!stakingWhitelist[msg.sender]) {
            revert NotWhitelisted();
        }
        _internalStakeForAddress(msg.sender, msg.sender, amount, 10_000);
    }

    /**
     * @notice Completes the unstaking process after the required duration
     * @dev Checks daily withdrawal limits before processing
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert DailyWithdrawalLimitExceeded if withdrawal would exceed daily limit
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     */
    function unstake(
        uint256 stakingStoreIndex
    ) external onlyBeneficiaryOrPayoutWallet(stakingStoreIndex) nonReentrant {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.unstakingRequestTime == 0) {
            revert UnstakingNotRequested();
        }

        if (
            currentStore.unstakingRequestTime + unstakingDuration >
            block.timestamp
        ) {
            revert UnstakingPeriodNotElapsed();
        }

        // Ensure the reward amount is up to date
        updateReward(stakingStoreIndex);

        uint256 rewardToSend = currentStore.reward - currentStore.paidOutReward;
        currentStore.paidOutReward += rewardToSend;

        uint256 principalWalletReward = (rewardToSend *
            _getCurrentPrincipalWalletShareBps(stakingStoreIndex)) / 10000;
        uint256 beneficiaryReward = rewardToSend - principalWalletReward;

        if (principalWalletReward > 0) {
            // Send tokens to delegator
            STAKING_TOKEN.safeTransferFrom(
                rewardsWallet,
                currentStore.principalPayoutWallet,
                principalWalletReward
            );
        }

        STAKING_TOKEN.safeTransferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            beneficiaryReward
        );
        currentStore.unstakingRequestTime = 0;
        currentStore.reward = 0;
        currentStore.stakingStartTime = uint64(block.timestamp);

        emit Unstaked(
            stakingStoreIndex,
            0,
            principalWalletReward,
            beneficiaryReward,
            currentStore.principalPayoutWallet,
            currentStore.beneficiary
        );
    }

    /**
     * @notice Unstakes the principal amount immediately
     * @dev Only possible for the principal unstaker
     * @param stakingStoreIndex Index of the staking store
     * @param amount Amount of principal to unstake
     * @custom:revert NotPrincipalUnstaker if caller is not the principal unstaker
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     * @custom:revert AmountExceedsStaked if amount exceeds staked principal
     */
    function unstakePrincipal(
        uint256 stakingStoreIndex,
        uint256 amount
    ) external nonReentrant {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        if (currentStore.unstakingRequestTime == 0) {
            revert UnstakingNotRequested();
        }
        if (
            currentStore.unstakingRequestTime + unstakingDuration >
            block.timestamp
        ) {
            revert UnstakingPeriodNotElapsed();
        }

        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }

        if (amount > currentStore.principal) {
            revert AmountExceedsStaked();
        }

        updateReward(stakingStoreIndex);
        uint256 principalToSend = amount;
        currentStore.principal = currentStore.principal - amount;

        uint256 rewardToSend = currentStore.reward - currentStore.paidOutReward;
        currentStore.paidOutReward += rewardToSend;

        currentStore.unstakingRequestTime = 0;
        currentStore.stakingStartTime = uint64(block.timestamp);

        uint256 principalWalletReward = (rewardToSend *
            _getCurrentPrincipalWalletShareBps(stakingStoreIndex)) / 10000;
        uint256 beneficiaryReward = rewardToSend - principalWalletReward;

        if (principalWalletReward > 0) {
            // Send tokens to delegator
            STAKING_TOKEN.safeTransferFrom(
                rewardsWallet,
                currentStore.principalPayoutWallet,
                principalWalletReward
            );
        }

        // Pay out principal
        STAKING_TOKEN.safeTransfer(
            currentStore.principalPayoutWallet,
            principalToSend
        );

        // Send remaining reward tokens to beneficiary
        STAKING_TOKEN.safeTransferFrom(
            rewardsWallet,
            currentStore.beneficiary,
            beneficiaryReward
        );

        emit Unstaked(
            stakingStoreIndex,
            principalToSend,
            principalWalletReward,
            beneficiaryReward,
            currentStore.principalPayoutWallet,
            currentStore.beneficiary
        );
    }

    /**
     * @notice Adds an address to the whitelist for staking
     * @dev Only callable by the contract owner
     * @param newStakerAddress The address to be whitelisted
     * @custom:revert AlreadyWhitelisted if the address is already whitelisted
     * @custom:event Emits StakerAddressAdded on success
     */
    function addWhitelistedStaker(address newStakerAddress) external onlyOwner {
        if (stakingWhitelist[newStakerAddress]) {
            revert AlreadyWhitelisted();
        }
        stakingWhitelist[newStakerAddress] = true;
        emit StakerAddressAdded(newStakerAddress);
    }

    /**
     * @notice Removes an address from the staking whitelist
     * @dev Only callable by the contract owner
     * @param stakerAddressToRemove The address to remove from the whitelist
     * @custom:revert NotWhitelisted if the address is not currently whitelisted
     * @custom:event Emits StakerAddressRemoved on success
     */
    function removeWhitelistedStaker(
        address stakerAddressToRemove
    ) external onlyOwner {
        if (!stakingWhitelist[stakerAddressToRemove]) {
            revert NotWhitelisted();
        }
        stakingWhitelist[stakerAddressToRemove] = false;
        emit StakerAddressRemoved(stakerAddressToRemove);
    }

    /**
     * @notice Calculates the accrued reward for a given staking store
     * @dev The reward is calculated based on the number of full days passed since staking started
     * @param stakingStoreIndex The index of the staking store
     * @return The total reward accumulated so far
     */
    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public view override returns (uint256) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        // Calculate number of full days that passed for staking store
        uint256 passedSeconds;
        if (currentStore.unstakingRequestTime > 0) {
            passedSeconds =
                currentStore.unstakingRequestTime -
                currentStore.stakingStartTime;
        } else {
            passedSeconds = block.timestamp - currentStore.stakingStartTime;
        }
        uint256 passedDays = passedSeconds / (24 * 60 * 60);

        // assumption: reward rate is measured in bps
        return (rewardRatePerDay * passedDays * currentStore.principal) / 10000;
    }

    /**
     * @notice Updates the reward amount for a given staking store
     * @dev Ensures the reward does not decrease
     * @param stakingStoreIndex The index of the staking store
     * @custom:assert The newly calculated reward must be greater than or equal to the current reward
     */
    function updateReward(uint256 stakingStoreIndex) internal {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        uint256 reward = getRewardForStakingStore(stakingStoreIndex);
        assert(reward >= currentStore.reward);

        currentStore.reward = reward;
    }

    /**
     * @notice Get the current principal wallet share basis points for a stake
     * @param stakeId The ID of the stake to check
     * @return The current principal wallet share in basis points
     */
    function getCurrentPrincipalWalletShareBps(
        uint256 stakeId
    ) public view returns (uint32) {
        return _getCurrentPrincipalWalletShareBps(stakeId);
    }
}
