// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseController } from "./BaseController.sol";
import { VaultManager } from "./VaultManager.sol";
import { IControlledVault } from "../interfaces/IControlledVault.sol";

/**
 * @title RewardsManager
 * @notice Abstract contract that manages rewards for controlled vaults
 * @dev Provides functionality to sell reward tokens for vault assets or claim rewards directly
 */
abstract contract RewardsManager is BaseController, VaultManager {
    /**
     * @notice Role identifier for addresses authorized to manage rewards
     */
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");

    /**
     * @notice Emitted when reward tokens are sold and converted to vault assets
     */
    event RewardsSold(address indexed vault, address indexed rewardAsset, uint256 rewards, uint256 assets);
    /**
     * @notice Emitted when reward tokens are claimed and sent to a receiver
     */
    event RewardsClaimed(address indexed vault, address indexed rewardAsset, address indexed receiver, uint256 rewards);

    /**
     * @notice Thrown when an invalid vault address is provided
     */
    error Reward_InvalidVault();
    /**
     * @notice Thrown when the reward asset is not approved for use
     */
    error Reward_NotRewardAsset();
    /**
     * @notice Thrown when the reward asset is the same as the vault asset
     */
    error Reward_SameAssets();
    /**
     * @notice Thrown when there are no rewards to process
     */
    error Reward_ZeroRewards();
    /**
     * @notice Thrown when the received assets are below the minimum expected amount
     */
    error Reward_SlippageTooHigh();

    /**
     * @notice Initializes the RewardsManager contract
     * @dev This function is called during contract initialization and is marked as onlyInitializing
     * to ensure it can only be called once during the initialization process
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __RewardsManager_init() internal onlyInitializing { }

    /**
     * @notice Sells reward tokens from a vault and converts them to vault assets
     * @dev Withdraws reward tokens from the vault, swaps them for vault assets using the swapper,
     * and deposits the received assets back into the vault
     * @param vault The address of the vault containing the reward tokens
     * @param rewardAsset The address of the reward token to sell
     * @param minAmountOut The minimum amount of vault assets expected from the swap
     * @param swapperData Additional data required by the swapper for the token swap
     * @return assets The amount of vault assets received from selling the rewards
     */
    function sellRewards(
        address vault,
        address rewardAsset,
        uint256 minAmountOut,
        bytes calldata swapperData
    )
        external
        nonReentrant
        onlyRole(REWARDS_MANAGER_ROLE)
        returns (uint256 assets)
    {
        (uint256 rewards, address vaultAsset) = _rewards(vault, rewardAsset);

        IControlledVault(vault).controllerWithdraw(rewardAsset, rewards, address(_swapper));
        assets = _swapper.swap(rewardAsset, rewards, vaultAsset, minAmountOut, vault, swapperData);
        IControlledVault(vault).controllerDeposit(assets);

        require(assets >= minAmountOut, Reward_SlippageTooHigh());

        emit RewardsSold(vault, rewardAsset, rewards, assets);
    }

    /**
     * @notice Claims reward tokens from a vault and sends them to the rewards collector
     * @dev Withdraws all available reward tokens from the vault and transfers them to the rewards collector
     * @param vault The address of the vault containing the reward tokens
     * @param rewardAsset The address of the reward token to claim
     * @return rewards The amount of reward tokens claimed and transferred
     */
    function claimRewards(
        address vault,
        address rewardAsset
    )
        external
        nonReentrant
        onlyRole(REWARDS_MANAGER_ROLE)
        returns (uint256 rewards)
    {
        (rewards,) = _rewards(vault, rewardAsset);

        address _rewardsCollector = rewardsCollector;
        IControlledVault(vault).controllerWithdraw(rewardAsset, rewards, _rewardsCollector);

        emit RewardsClaimed(vault, rewardAsset, _rewardsCollector, rewards);
    }

    /**
     * @notice Internal function to get the amount of reward tokens in a vault
     * @dev Validates the vault and reward asset, then retrieves the balance of the reward asset in the vault
     * @param vault The address of the vault to check for rewards
     * @param rewardAsset The address of the reward token to check
     * @return rewards The amount of reward tokens available in the vault
     * @return vaultAsset The address of the vault's primary asset (for cache purposes)
     */
    function _rewards(
        address vault,
        address rewardAsset
    )
        internal
        view
        returns (uint256 rewards, address vaultAsset)
    {
        require(isVault(vault), Reward_InvalidVault());
        require(isRewardAsset[rewardAsset], Reward_NotRewardAsset());
        vaultAsset = IControlledVault(vault).asset();
        require(vaultAsset != rewardAsset, Reward_SameAssets());
        rewards = IERC20(rewardAsset).balanceOf(vault);
        require(rewards > 0, Reward_ZeroRewards());
    }
}
