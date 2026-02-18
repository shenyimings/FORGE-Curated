// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

struct VaultRewardState {
    address rewardToken;
    uint32 lastAccumulatedTime;
    uint32 endTime;
    // Slot #2
    // If secondary rewards are enabled, they will be streamed to the accounts via
    // an annual emission rate. If the same reward token is also issued by the LP pool,
    // those tokens will be added on top of the annual emission rate. If the vault is under
    // automatic reinvestment mode, the secondary reward token cannot be sold.
    uint128 emissionRatePerYear; // in internal token precision
    uint128 accumulatedRewardPerVaultShare;
}

enum RewardPoolType {
    _UNUSED,
    AURA,
    CONVEX_MAINNET,
    CONVEX_ARBITRUM
}

struct RewardPoolStorage {
    address rewardPool;
    uint32 lastClaimTimestamp;
    uint32 forceClaimAfter;
}

/// Each reward manager is responsible for claiming rewards for a given protocol.
/// it will be called through a delegatecall from the vault to avoid token transfers
/// of staked tokens.
interface IRewardManager {

    event VaultRewardTransfer(address token, address account, uint256 amount);
    event VaultRewardUpdate(address rewardToken, uint128 emissionRatePerYear, uint32 endTime);

    /// @notice Returns the current reward claim method and reward state
    /// @return rewardStates Array of vault reward states
    /// @return rewardPool Reward pool storage
    function getRewardSettings() external view returns (
        VaultRewardState[] memory rewardStates,
        RewardPoolStorage memory rewardPool
    );

    /// @notice Returns the reward debt for the given reward token and account
    /// @param rewardToken Address of the reward token
    /// @param account Address of the account
    /// @return rewardDebt The reward debt for the account
    function getRewardDebt(address rewardToken, address account) external view returns (
        uint256 rewardDebt
    );


    /// @notice Updates account rewards during enter and exit vault operations, only
    /// callable via delegatecall from inside the vault
    /// @param account Address of the account
    /// @param effectiveSupplyBefore Total vault shares before the operation
    /// @param accountSharesBefore Number of shares before the operation
    /// @param accountSharesAfter Number of shares after the operation
    /// @param sharesInEscrow Whether the shares are in escrow
    function updateAccountRewards(
        address account,
        uint256 effectiveSupplyBefore,
        uint256 accountSharesBefore,
        uint256 accountSharesAfter,
        bool sharesInEscrow
    ) external returns (uint256[] memory rewards);

    /// @notice Sets a secondary reward rate for a given token, only callable via the owner
    /// @param index Index of the reward token
    /// @param rewardToken Address of the reward token
    /// @param emissionRatePerYear Emission rate per year for the token
    /// @param endTime End time for the emission rate
    function updateRewardToken(
        uint256 index,
        address rewardToken,
        uint128 emissionRatePerYear,
        uint32 endTime
    ) external;

    /// @notice Migrates the reward pool to a new reward pool, needs to be called initially
    /// to set the reward pool storage and when the reward pool is updated.
    /// @param poolToken The pool token to migrate
    /// @param newRewardPool The new reward pool storage configuration
    function migrateRewardPool(address poolToken, RewardPoolStorage memory newRewardPool) external;

    /// @notice Claims all the rewards for the entire vault and updates the accumulators
    function claimRewardTokens() external;
}