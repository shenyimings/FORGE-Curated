// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./StakingErrorsAndEvents.sol";
import "forge-std/console.sol";
// Events

abstract contract DIAStakingCommons is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => uint256[]) internal stakingIndicesByBeneficiary;
    mapping(address => uint256[]) internal stakingIndicesByPrincipalUnstaker;
    mapping(address => uint256[]) internal stakingIndicesByPayoutWallet;

    uint256 public stakingIndex;

    struct PendingShareUpdate {
        uint32 newShareBps;
        uint64 requestTime;
    }

    mapping(uint256 => PendingShareUpdate) public pendingShareUpdates;
    uint64 public constant SHARE_UPDATE_GRACE_PERIOD = 1 days;

    /// @notice ERC20 token used for staking.
    IERC20 public immutable STAKING_TOKEN;

    struct StakingStore {
        address beneficiary;
        address principalPayoutWallet;
        address principalUnstaker;
        uint256 principal;
        uint256 reward;
        uint256 paidOutReward;
        uint64 stakingStartTime;
        uint64 unstakingRequestTime;
        uint32 principalWalletShareBps;
    }

    uint256 public tokensStaked;

    uint256 public stakingLimit;

    /// @notice How long (in seconds) for unstaking to take place
    uint256 public unstakingDuration;

    uint256 public totalDailyWithdrawals;

    uint256 public lastWithdrawalResetDay;
    uint256 public dailyWithdrawalThreshold = 100000 * 10 ** 18; // Set threshold as needed
    uint256 public withdrawalCapBps = 1000; // 1000 bps = 10%

    /// @notice Mapping of staking index to corresponding staking store.
    mapping(uint256 => DIAStakingCommons.StakingStore) public stakingStores;

    modifier onlyBeneficiaryOrPayoutWallet(uint256 stakingStoreIndex) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

        if (
            msg.sender != currentStore.beneficiary &&
            msg.sender != currentStore.principalPayoutWallet
        ) {
            revert AccessDenied();
        }
        _;
    }

    /**
     * @notice Updates the duration required before unstaking can be completed.
     * @dev Only callable by the contract owner.
     * @param newDuration The new unstaking duration, in seconds.
     * @custom:revert UnstakingDurationTooShort() if the new duration is less than 1 day.
     * @custom:revert UnstakingDurationTooLong() if the new duration exceeds 20 days.
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

    function setWithdrawalCapBps(uint256 newBps) external onlyOwner {
        if (newBps > 10000) {
            revert InvalidWithdrawalCap(newBps);
        }

        uint256 oldCap = withdrawalCapBps;
        withdrawalCapBps = newBps;

        emit WithdrawalCapUpdated(oldCap, newBps); // Emit event with old and new values
    }

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

    function getStakingIndicesByBeneficiary(
        address beneficiary
    ) external view returns (uint256[] memory) {
        return stakingIndicesByBeneficiary[beneficiary];
    }

    function getStakingIndicesByPrincipalUnstaker(
        address unstaker
    ) external view returns (uint256[] memory) {
        return stakingIndicesByPrincipalUnstaker[unstaker];
    }

    function getStakingIndicesByPayoutWallet(
        address payoutWallet
    ) external view returns (uint256[] memory) {
        return stakingIndicesByPayoutWallet[payoutWallet];
    }

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

    function _internalStakeForAddress(
        address sender,
        address beneficiaryAddress,
        uint256 amount,
        uint32 principalWalletShareBps
    ) internal returns (uint256 index) {
        if (principalWalletShareBps > 10000)
            revert InvalidPrincipalWalletShare();

        if (amount < minimumStake) {
            revert AmountBelowMinimumStake(amount);
        }

        // Transfer tokens
        STAKING_TOKEN.safeTransferFrom(sender, address(this), amount);

        // Create staking entry
        stakingIndex++;
        StakingStore storage newStore = stakingStores[stakingIndex];
        newStore.beneficiary = beneficiaryAddress;
        newStore.principalPayoutWallet = sender;
        newStore.principal = amount;
        newStore.stakingStartTime = uint64(block.timestamp);
        newStore.principalWalletShareBps = principalWalletShareBps;
        newStore.principalUnstaker = sender;

        // Track stake info
        tokensStaked += amount;
        stakingIndicesByBeneficiary[beneficiaryAddress].push(stakingIndex);
        stakingIndicesByPrincipalUnstaker[sender].push(stakingIndex);
        stakingIndicesByPayoutWallet[sender].push(stakingIndex);

        emit Staked(beneficiaryAddress, stakingIndex, amount);

        return stakingIndex;
    }

    /**
     * @notice Updates the principal payout wallet for a given staking index.
     * @dev Only callable by the contract owner.
     * @param newWallet New wallet address for receiving the principal.
     * @param stakingStoreIndex Index of the staking store.
     */
    function updatePrincipalPayoutWallet(
        address newWallet,
        uint256 stakingStoreIndex
    ) external {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];

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
            currentStore.principalPayoutWallet,
            newWallet,
            stakingStoreIndex
        );
    }

    /**
     * @notice Allows the current unstaker to update the unstaker.
     * @param newUnstaker New address allowed to unstake the principal.
     * @param stakingStoreIndex Index of the staking store.
     */
    function updatePrincipalUnstaker(
        address newUnstaker,
        uint256 stakingStoreIndex
    ) external {
        if (newUnstaker == address(0)) revert ZeroAddress();
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.principalUnstaker != msg.sender) {
            revert NotPrincipalUnstaker();
        }

        currentStore.principalUnstaker = newUnstaker;
    }

    /**
     * @notice Requests unstaking, starting the waiting period.
     * @dev Can only be called by the beneficiary.
     * @param stakingStoreIndex Index of the staking store.
     */
    function requestUnstake(
        uint256 stakingStoreIndex
    ) external nonReentrant onlyBeneficiaryOrPayoutWallet(stakingStoreIndex) {
        StakingStore storage currentStore = stakingStores[stakingStoreIndex];
        if (currentStore.unstakingRequestTime != 0) {
            revert AlreadyRequestedUnstake();
        }

        currentStore.unstakingRequestTime = uint64(block.timestamp);
        emit UnstakeRequested(msg.sender, stakingStoreIndex);
    }

    function _getCurrentPrincipalWalletShareBps(
        uint256 stakeId
    ) internal view returns (uint32) {
        PendingShareUpdate memory pending = pendingShareUpdates[stakeId];

        if (
            pending.requestTime > 0 &&
            block.timestamp >= pending.requestTime + SHARE_UPDATE_GRACE_PERIOD
        ) {
            return pending.newShareBps;
        }

        return stakingStores[stakeId].principalWalletShareBps;
    }

    function requestPrincipalWalletShareUpdate(
        uint256 stakeId,
        uint32 newShareBps
    ) external {
        if (msg.sender != stakingStores[stakeId].beneficiary) {
            revert NotBeneficiary();
        }

        if (newShareBps > 10000) revert InvalidPrincipalWalletShare();

        pendingShareUpdates[stakeId] = PendingShareUpdate({
            newShareBps: newShareBps,
            requestTime: uint64(block.timestamp)
        });

        emit PrincipalWalletShareUpdateRequested(
            stakeId,
            newShareBps,
            block.timestamp
        );
    }
}
