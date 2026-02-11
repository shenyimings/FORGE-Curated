// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./StakingErrorsAndEvents.sol";

/**
 * @title DIAExternalStaking
 * @notice A staking contract that allows users to stake tokens and earn rewards
 * @dev Implements external staking functionality with principal/reward sharing and daily withdrawal limits
 */
contract DIAExternalStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Mapping of beneficiary addresses to their staking indices
    mapping(address => uint256[]) internal stakingIndicesByBeneficiary;

    /// @notice Mapping of principal unstaker addresses to their staking indices
    mapping(address => uint256[]) internal stakingIndicesByPrincipalUnstaker;

    /// @notice Mapping of payout wallet addresses to their staking indices
    mapping(address => uint256[]) internal stakingIndicesByPayoutWallet;

    /// @notice Current staking index counter
    uint256 public stakingIndex;

    /// @notice Structure for pending share updates
    struct PendingShareUpdate {
        uint32 newShareBps; // New share in basis points
        uint64 requestTime; // Time when update was requested
    }

    /// @notice Mapping of stake IDs to their pending share updates
    mapping(uint256 => PendingShareUpdate) public pendingShareUpdates;

    /// @notice Grace period for share updates (1 day)
    uint64 public constant SHARE_UPDATE_GRACE_PERIOD = 1 days;

    /// @notice ERC20 token used for staking
    IERC20 public immutable STAKING_TOKEN;

    /// @notice Structure for storing staking information
    struct ExternalStakingStore {
        address beneficiary; // Address receiving rewards
        address principalPayoutWallet; // Address receiving principal
        address principalUnstaker; // Address allowed to unstake principal
        uint256 principal; // Amount of tokens staked
        uint256 poolShares; // Share of the total pool
        uint64 stakingStartTime; // When staking began
        uint64 unstakingRequestTime; // When unstaking was requested
        uint32 principalWalletShareBps; // Share of rewards going to principal wallet
    }

    /// @notice Total size of the staking pool
    uint256 public totalPoolSize;

    /// @notice Total amount of pool shares
    uint256 public totalShareAmount;

    /// @notice Total amount of tokens staked
    uint256 public tokensStaked;

    /// @notice Maximum amount of tokens that can be staked
    uint256 public stakingLimit;

    /// @notice Duration required before unstaking can be completed
    uint256 public unstakingDuration;

    /// @notice Total amount withdrawn in the current day
    uint256 public totalDailyWithdrawals;

    /// @notice Timestamp of the last day when withdrawals were reset
    uint256 public lastWithdrawalResetDay;

    /// @notice Minimum pool size required to trigger withdrawal limits
    uint256 public dailyWithdrawalThreshold = 100000 * 10 ** 18;

    /// @notice Maximum percentage of pool that can be withdrawn per day (in basis points)
    uint256 public withdrawalCapBps = 1000; // 1000 bps = 10%

    /// @notice Mapping of staking indices to their corresponding staking stores
    mapping(uint256 => ExternalStakingStore) public stakingStores;

    /**
     * @notice Modifier to check if caller is beneficiary or payout wallet
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert AccessDenied if caller is neither beneficiary nor payout wallet
     */
    modifier onlyBeneficiaryOrPayoutWallet(uint256 stakingStoreIndex) {
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        if (
            msg.sender != currentStore.beneficiary &&
            msg.sender != currentStore.principalUnstaker
        ) {
            revert AccessDenied();
        }
        _;
    }

    /**
     * @notice Modifier to check daily withdrawal limits
     * @param amount Amount to be withdrawn
     * @custom:revert DailyWithdrawalLimitExceeded if withdrawal would exceed daily limit
     */
    modifier checkDailyWithdrawalLimit(uint256 amount) {
        if (block.timestamp / SECONDS_IN_A_DAY > lastWithdrawalResetDay) {
            totalDailyWithdrawals = 0;
            lastWithdrawalResetDay = block.timestamp / SECONDS_IN_A_DAY;
        }

        if (totalPoolSize > dailyWithdrawalThreshold) {
            uint256 availableDailyLimit = (totalPoolSize * withdrawalCapBps) /
                10000;
            if (totalDailyWithdrawals + amount > availableDailyLimit) {
                revert DailyWithdrawalLimitExceeded();
            }
        }
        _;
    }

    /**
     * @notice Initializes the contract with staking parameters
     * @param _unstakingDuration Duration required before unstaking can be completed
     * @param _stakingTokenAddress Address of the ERC20 token used for staking
     * @param _stakingLimit Maximum amount of tokens that can be staked
     * @custom:revert ZeroAddress if staking token address is zero
     */
    constructor(
        uint256 _unstakingDuration,
        address _stakingTokenAddress,
        uint256 _stakingLimit
    ) Ownable(msg.sender) {
        if (_stakingTokenAddress == address(0)) revert ZeroAddress();
        unstakingDuration = _unstakingDuration;
        STAKING_TOKEN = IERC20(_stakingTokenAddress);
        stakingLimit = _stakingLimit;
        lastWithdrawalResetDay = block.timestamp;
    }

    /**
     * @notice Allows a user to stake tokens directly
     * @param amount Amount of tokens to stake
     * @param principalWalletShareBps Share of rewards going to principal wallet in basis points
     */
    function stake(
        uint256 amount,
        uint32 principalWalletShareBps
    ) public nonReentrant {
        _stake(msg.sender, amount, principalWalletShareBps, msg.sender);
    }

    /**
     * @notice Stakes tokens on behalf of a given address
     * @param beneficiaryAddress Address receiving the staking rewards
     * @param amount Amount of tokens to be staked
     * @param principalWalletShareBps Share of rewards going to principal wallet in basis points
     */
    function stakeForAddress(
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps
    ) public nonReentrant {
        _stake(beneficiaryAddress, amount, principalWalletShareBps, msg.sender);
    }

    /**
     * @notice Internal function to handle staking logic
     * @param beneficiaryAddress Address receiving the staking rewards
     * @param amount Amount of tokens to be staked
     * @param principalWalletShareBps Share of rewards going to principal wallet in basis points
     * @param staker Address performing the stake operation
     * @custom:revert AmountAboveStakingLimit if amount exceeds staking limit
     * @custom:revert InvalidPrincipalWalletShare if share exceeds 100%
     * @custom:revert AmountBelowMinimumStake if amount is below minimum stake
     */
    function _stake(
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps,
        address staker
    ) internal {
        if (amount > (stakingLimit - tokensStaked)) {
            revert AmountAboveStakingLimit(amount);
        }

        if (principalWalletShareBps > 10000)
            revert InvalidPrincipalWalletShare();

        if (amount < minimumStake) {
            revert AmountBelowMinimumStake(amount);
        }

        STAKING_TOKEN.safeTransferFrom(staker, address(this), amount);

        uint256 poolSharesGiven = 0;
        if (totalShareAmount == 0) {
            poolSharesGiven = amount;
        } else {
            poolSharesGiven = (amount * totalShareAmount) / totalPoolSize;
        }

        totalPoolSize += amount;
        totalShareAmount += poolSharesGiven;

        stakingIndex++;
        ExternalStakingStore storage newStore = stakingStores[stakingIndex];
        newStore.beneficiary = beneficiaryAddress;
        newStore.principalPayoutWallet = staker;
        newStore.principal = amount;
        newStore.poolShares = poolSharesGiven;
        newStore.stakingStartTime = uint64(block.timestamp);
        newStore.principalWalletShareBps = principalWalletShareBps;
        newStore.principalUnstaker = staker;

        tokensStaked += amount;
        stakingIndicesByBeneficiary[beneficiaryAddress].push(stakingIndex);
        stakingIndicesByPrincipalUnstaker[staker].push(stakingIndex);
        stakingIndicesByPayoutWallet[staker].push(stakingIndex);

        emit Staked(beneficiaryAddress, stakingIndex, amount);
    }

    /**
     * @notice Updates the duration required before unstaking can be completed
     * @param newDuration New unstaking duration in seconds
     * @custom:revert UnstakingDurationTooShort if duration is less than 1 day
     * @custom:revert UnstakingDurationTooLong if duration exceeds 20 days
     */
    function setUnstakingDuration(uint256 newDuration) external onlyOwner {
        if (newDuration < 1 days) {
            revert UnstakingDurationTooShort();
        }
        if (newDuration > 20 days) {
            revert UnstakingDurationTooLong();
        }
        emit UnstakingDurationUpdated(unstakingDuration, newDuration);
        unstakingDuration = newDuration;
    }

    /**
     * @notice Updates the withdrawal cap in basis points
     * @param newBps New cap value in basis points
     * @custom:revert InvalidWithdrawalCap if new cap exceeds 10000 bps
     */
    function setWithdrawalCapBps(uint256 newBps) external onlyOwner {
        if (newBps > 10000) {
            revert InvalidWithdrawalCap(newBps);
        }
        uint256 oldCap = withdrawalCapBps;
        withdrawalCapBps = newBps;
        emit WithdrawalCapUpdated(oldCap, newBps);
    }

    /**
     * @notice Updates the daily withdrawal threshold
     * @param newThreshold New threshold value
     * @custom:revert InvalidDailyWithdrawalThreshold if new threshold is 0
     */
    function setDailyWithdrawalThreshold(
        uint256 newThreshold
    ) external onlyOwner {
        if (newThreshold <= 0) {
            revert InvalidDailyWithdrawalThreshold(newThreshold);
        }
        uint256 oldThreshold = dailyWithdrawalThreshold;
        dailyWithdrawalThreshold = newThreshold;
        emit DailyWithdrawalThresholdUpdated(oldThreshold, newThreshold);
    }

    /**
     * @notice Gets all staking indices for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Array of staking indices
     */
    function getStakingIndicesByBeneficiary(
        address beneficiary
    ) external view returns (uint256[] memory) {
        return stakingIndicesByBeneficiary[beneficiary];
    }

    /**
     * @notice Gets all staking indices for a principal unstaker
     * @param unstaker Address of the principal unstaker
     * @return Array of staking indices
     */
    function getStakingIndicesByPrincipalUnstaker(
        address unstaker
    ) external view returns (uint256[] memory) {
        return stakingIndicesByPrincipalUnstaker[unstaker];
    }

    /**
     * @notice Gets all staking indices for a payout wallet
     * @param payoutWallet Address of the payout wallet
     * @return Array of staking indices
     */
    function getStakingIndicesByPayoutWallet(
        address payoutWallet
    ) external view returns (uint256[] memory) {
        return stakingIndicesByPayoutWallet[payoutWallet];
    }

    /**
     * @notice Internal function to remove a staking index from an address mapping
     * @param user Address to remove index from
     * @param _stakingIndex Index to remove
     * @param indexMap Mapping to remove from
     */
    function _removeStakingIndexFromAddressMapping(
        address user,
        uint256 _stakingIndex,
        mapping(address => uint256[]) storage indexMap
    ) internal {
        uint256[] storage indices = indexMap[user];
        for (uint256 i = 0; i < indices.length; i++) {
            if (indices[i] == _stakingIndex) {
                indices[i] = indices[indices.length - 1];
                indices.pop();
                break;
            }
        }
    }

    /**
     * @notice Updates the principal payout wallet for a stake
     * @param newWallet New wallet address for receiving principal
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert ZeroAddress if new wallet is zero address
     * @custom:revert NotPrincipalUnstaker if caller is not the principal unstaker
     */
    function updatePrincipalPayoutWallet(
        address newWallet,
        uint256 stakingStoreIndex
    ) external {
        if (newWallet == address(0)) revert ZeroAddress();
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        address oldWallet = currentStore.principalPayoutWallet;
        currentStore.principalPayoutWallet = newWallet;

        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }

        _removeStakingIndexFromAddressMapping(
            oldWallet,
            stakingStoreIndex,
            stakingIndicesByPayoutWallet
        );
        stakingIndicesByPayoutWallet[newWallet].push(stakingStoreIndex);

        emit PrincipalPayoutWalletUpdated(
            oldWallet,
            newWallet,
            stakingStoreIndex
        );
    }

    /**
     * @notice Updates the principal unstaker for a stake
     * @param newUnstaker New address allowed to unstake principal
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert ZeroAddress if new unstaker is zero address
     * @custom:revert NotPrincipalUnstaker if caller is not the current principal unstaker
     */
    function updatePrincipalUnstaker(
        address newUnstaker,
        uint256 stakingStoreIndex
    ) external {
        if (newUnstaker == address(0)) revert ZeroAddress();
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }
        currentStore.principalUnstaker = newUnstaker;
    }

    /**
     * @notice Requests unstaking, starting the waiting period
     * @param stakingStoreIndex Index of the staking store
     * @custom:revert AlreadyRequestedUnstake if unstaking was already requested
     * @custom:revert AccessDenied if caller is not beneficiary or payout wallet
     */
    function requestUnstake(
        uint256 stakingStoreIndex
    ) external nonReentrant onlyBeneficiaryOrPayoutWallet(stakingStoreIndex) {
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        if (currentStore.unstakingRequestTime != 0) {
            revert AlreadyRequestedUnstake();
        }
        currentStore.unstakingRequestTime = uint64(block.timestamp);
        emit UnstakeRequested(msg.sender, stakingStoreIndex);
    }

    /**
     * @notice Completes the unstaking process after the required duration
     * @param stakingStoreIndex Index of the staking store
     * @param amount Amount to unstake
     * @custom:revert UnstakingNotRequested if unstaking was not requested
     * @custom:revert UnstakingPeriodNotElapsed if unstaking period has not elapsed
     * @custom:revert AmountExceedsStaked if amount exceeds staked amount
     * @custom:revert DailyWithdrawalLimitExceeded if withdrawal would exceed daily limit
     */
    function unstake(
        uint256 stakingStoreIndex,
        uint256 amount
    )
        external
        nonReentrant
        onlyBeneficiaryOrPayoutWallet(stakingStoreIndex)
        checkDailyWithdrawalLimit(amount)
    {
        ExternalStakingStore storage currentStore = stakingStores[
            stakingStoreIndex
        ];
        if (currentStore.unstakingRequestTime == 0) {
            revert UnstakingNotRequested();
        }

        if (
            currentStore.unstakingRequestTime + unstakingDuration >
            block.timestamp
        ) {
            revert UnstakingPeriodNotElapsed();
        }

        uint256 currentAmountOfPool = (currentStore.poolShares *
            totalPoolSize) / totalShareAmount;
        if (amount > currentAmountOfPool) {
            revert AmountExceedsStaked();
        }

        uint256 poolSharesUnstakeAmount = (currentStore.poolShares * amount) /
            currentAmountOfPool;
        uint256 principalUnstakeAmount = (currentStore.principal * amount) /
            currentAmountOfPool;
        uint256 rewardUnstakeAmount = amount - principalUnstakeAmount;

        uint256 principalToSend = principalUnstakeAmount;
        uint256 rewardToSend = rewardUnstakeAmount;
        currentStore.principal =
            currentStore.principal -
            principalUnstakeAmount;
        tokensStaked -= principalUnstakeAmount;
        currentStore.poolShares -= poolSharesUnstakeAmount;
        currentStore.unstakingRequestTime = 0;
        currentStore.stakingStartTime = uint64(block.timestamp);

        totalDailyWithdrawals += amount;
        totalPoolSize -= amount;
        totalShareAmount -= poolSharesUnstakeAmount;

        uint256 principalWalletReward = (rewardToSend *
            _getCurrentPrincipalWalletShareBps(stakingStoreIndex)) / 10000;
        uint256 beneficiaryReward = rewardToSend - principalWalletReward;

        if (principalWalletReward > 0) {
            STAKING_TOKEN.safeTransfer(
                currentStore.principalPayoutWallet,
                principalWalletReward
            );
        }

        STAKING_TOKEN.safeTransfer(
            currentStore.principalPayoutWallet,
            principalToSend
        );
        STAKING_TOKEN.safeTransfer(currentStore.beneficiary, beneficiaryReward);

        emit Unstaked(
            stakingStoreIndex,
            principalToSend,
            principalWalletReward,
            beneficiaryReward,
            currentStore.principalPayoutWallet,
            currentStore.beneficiary
        );
    }

    function addRewardToPool(uint256 amount) public {
        STAKING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        totalPoolSize += amount;
        emit RewardAdded(amount, msg.sender);
    }

    /**
     * @notice Gets the current principal wallet share basis points for a stake
     * @param stakingStoreIndex ID of the stake
     * @return Current principal wallet share in basis points
     */
    function _getCurrentPrincipalWalletShareBps(
        uint256 stakingStoreIndex
    ) internal view returns (uint32) {
        PendingShareUpdate memory pending = pendingShareUpdates[stakingStoreIndex];
        if (
            pending.requestTime > 0 &&
            block.timestamp >= pending.requestTime + SHARE_UPDATE_GRACE_PERIOD
        ) {
            return pending.newShareBps;
        }

        return stakingStores[stakingStoreIndex].principalWalletShareBps;
    }

    /**
     * @notice Gets the current principal wallet share basis points for a stake
     * @param stakingStoreIndex of the stake
     * @return Current principal wallet share in basis points
     */
    function getCurrentPrincipalWalletShareBps(
        uint256 stakingStoreIndex
    ) public view returns (uint32) {
        return _getCurrentPrincipalWalletShareBps(stakingStoreIndex);
    }

    /**
     * @notice Calculates the reward for a given staking store
     * @param stakingStoreIndex Index of the staking store
     * @return Amount of rewards available
     */
    function getRewardForStakingStore(
        uint256 stakingStoreIndex
    ) public view returns (uint256, uint256) {
        ExternalStakingStore storage store = stakingStores[stakingStoreIndex];
        uint256 claimableTokens = (store.poolShares * totalPoolSize) /
            totalShareAmount;
        uint256 fullReward = claimableTokens - store.principal;
				uint256 principalWalletReward = (fullReward * store.principalWalletShareBps) / 10000;
				return (principalWalletReward, fullReward - principalWalletReward);
    }

    /**
     * @notice Requests an update to the principal wallet share
     * @param stakingStoreIndex of the stake
     * @param newShareBps New share in basis points
     * @custom:revert NotBeneficiary if caller is not the beneficiary
     * @custom:revert InvalidPrincipalWalletShare if new share exceeds 100%
     */
    function requestPrincipalWalletShareUpdate(
        uint256 stakingStoreIndex,
        uint32 newShareBps
    ) external {
        if (msg.sender != stakingStores[stakingStoreIndex].principalUnstaker) {
            revert NotPrincipalUnstaker();
        }
        if (newShareBps > 10000) revert InvalidPrincipalWalletShare();

        pendingShareUpdates[stakingStoreIndex] = PendingShareUpdate({
            newShareBps: newShareBps,
            requestTime: uint64(block.timestamp)
        });

        emit PrincipalWalletShareUpdateRequested(
            stakingStoreIndex,
            newShareBps,
            block.timestamp
        );
    }
}
