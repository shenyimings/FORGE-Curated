// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IRewardManager.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {Unauthorized} from "../interfaces/Errors.sol";
import {DEFAULT_PRECISION, ADDRESS_REGISTRY, YEAR} from "../utils/Constants.sol";
import {TypeConvert} from "../utils/TypeConvert.sol";
import {IEIP20NonStandard} from "../interfaces/IEIP20NonStandard.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";

abstract contract AbstractRewardManager is IRewardManager, ReentrancyGuardTransient {
    using TypeConvert for uint256;
    using TokenUtils for ERC20;

    modifier onlyUpgradeAdmin() {
        if (msg.sender != ADDRESS_REGISTRY.upgradeAdmin()) revert Unauthorized(msg.sender);
        _;
    }

    // Uses custom storage slots to avoid collisions with other contracts
    uint256 private constant REWARD_POOL_SLOT = 1000001;
    uint256 private constant VAULT_REWARD_STATE_SLOT = 1000002;
    uint256 private constant ACCOUNT_REWARD_DEBT_SLOT = 1000003;
    uint256 private constant ACCOUNT_ESCROW_STATE_SLOT = 1000004;

    function _getRewardPoolSlot() internal pure returns (RewardPoolStorage storage store) {
        assembly { store.slot := REWARD_POOL_SLOT }
    }

    function _getVaultRewardStateSlot() internal pure returns (VaultRewardState[] storage store) {
        assembly { store.slot := VAULT_REWARD_STATE_SLOT }
    }

    function _getAccountRewardDebtSlot() internal pure returns (
        mapping(address account => mapping(address rewardToken => uint256 rewardDebt)) storage store
    ) {
        assembly { store.slot := ACCOUNT_REWARD_DEBT_SLOT }
    }

    /// @inheritdoc IRewardManager
    function migrateRewardPool(address poolToken, RewardPoolStorage memory newRewardPool) external override onlyUpgradeAdmin nonReentrant {
        // Claim all rewards from the previous reward pool before withdrawing
        uint256 effectiveSupplyBefore = IYieldStrategy(address(this)).effectiveSupply();
        _claimVaultRewards(effectiveSupplyBefore, _getVaultRewardStateSlot());
        RewardPoolStorage memory oldRewardPool = _getRewardPoolSlot();

        if (oldRewardPool.rewardPool != address(0)) {
            _withdrawFromPreviousRewardPool(oldRewardPool);

            // Clear approvals on the old pool.
            ERC20(poolToken).checkRevoke(address(oldRewardPool.rewardPool));
        }

        uint256 poolTokens = ERC20(poolToken).balanceOf(address(this));
        _depositIntoNewRewardPool(poolToken, poolTokens, newRewardPool);

        // Set the last claim timestamp to the current block timestamp since we re claiming all the rewards
        // earlier in this method.
        _getRewardPoolSlot().lastClaimTimestamp = uint32(block.timestamp);
        _getRewardPoolSlot().rewardPool = newRewardPool.rewardPool;
        _getRewardPoolSlot().forceClaimAfter = newRewardPool.forceClaimAfter;
    }


    /// @inheritdoc IRewardManager
    function getRewardSettings() external view override returns (
        VaultRewardState[] memory rewardStates,
        RewardPoolStorage memory rewardPool
    ) {
        rewardStates = _getVaultRewardStateSlot();
        rewardPool = _getRewardPoolSlot();
    }

    /// @inheritdoc IRewardManager
    function getRewardDebt(address rewardToken, address account) external view override returns (uint256) {
        return _getAccountRewardDebtSlot()[rewardToken][account];
    }

    /// @inheritdoc IRewardManager
    function updateRewardToken(
        uint256 index,
        address rewardToken,
        uint128 emissionRatePerYear,
        uint32 endTime
    ) external override onlyUpgradeAdmin {
        uint256 effectiveSupplyBefore = IYieldStrategy(address(this)).effectiveSupply();
        uint256 numRewardStates = _getVaultRewardStateSlot().length;

        if (index < numRewardStates) {
            VaultRewardState memory state = _getVaultRewardStateSlot()[index];
            // Safety check to ensure that the correct token is specified, we can never change the
            // token address once set.
            require(state.rewardToken == rewardToken);
            // Modifies the emission rate on an existing token, direct claims of the token will
            // not be affected by the emission rate.
            // First accumulate under the old regime up to the current time. Even if the previous
            // emissionRatePerYear is zero this will still set the lastAccumulatedTime to the current
            // blockTime.
            _accumulateSecondaryRewardViaEmissionRate(index, state, effectiveSupplyBefore);

            // Save the new emission rates
            state.emissionRatePerYear = emissionRatePerYear;
            if (state.emissionRatePerYear == 0) {
                state.endTime = 0;
            } else {
                require(block.timestamp < endTime);
                state.endTime = endTime;
            }
            _getVaultRewardStateSlot()[index] = state;
        } else if (index == numRewardStates) {
            // This sets a new reward token, ensure that the current slot is empty
            VaultRewardState[] storage states = _getVaultRewardStateSlot();
            // If no emission rate is set then governance is just adding a token that can be claimed
            // via the LP tokens without an emission rate. These settings will be left empty and the
            // subsequent _claimVaultRewards method will set the initial accumulatedRewardPerVaultShare.
            if (0 < emissionRatePerYear) require(block.timestamp < endTime);

            states.push(VaultRewardState({
                rewardToken: rewardToken,
                lastAccumulatedTime: uint32(block.timestamp),
                endTime: endTime,
                emissionRatePerYear: emissionRatePerYear,
                accumulatedRewardPerVaultShare: 0
            }));
        } else {
            // Can only append or modify existing tokens
            revert();
        }

        // Claim all vault rewards up to the current time
        _claimVaultRewards(effectiveSupplyBefore, _getVaultRewardStateSlot());
        emit VaultRewardUpdate(rewardToken, emissionRatePerYear, endTime);
    }

    /// @notice Claims all the rewards for the entire vault and updates the accumulators. Does not
    /// update emission rewarders since those are automatically updated on every account claim.
    function claimRewardTokens() external nonReentrant {
        // This method is not executed from inside enter or exit vault positions, so this total
        // vault shares value is valid.
        uint256 effectiveSupplyBefore = IYieldStrategy(address(this)).effectiveSupply();
        _claimVaultRewards(effectiveSupplyBefore, _getVaultRewardStateSlot());
    }

    /// @inheritdoc IRewardManager
    function updateAccountRewards(
        address account,
        uint256 effectiveSupplyBefore,
        uint256 accountSharesBefore,
        uint256 accountSharesAfter,
        bool sharesInEscrow
    ) external returns (uint256[] memory rewards) {
        // Short circuit in this case, no rewards to claim
        if (sharesInEscrow && accountSharesAfter > 0) return rewards;

        VaultRewardState[] memory state = _getVaultRewardStateSlot();
        _claimVaultRewards(effectiveSupplyBefore, state);
        rewards = new uint256[](state.length);

        for (uint256 i; i < state.length; i++) {
            if (sharesInEscrow && accountSharesAfter == 0) {
                delete _getAccountRewardDebtSlot()[state[i].rewardToken][account];
                continue;
            }

            if (0 < state[i].emissionRatePerYear) {
                // Accumulate any rewards with an emission rate here
                _accumulateSecondaryRewardViaEmissionRate(i, state[i], effectiveSupplyBefore);
            }

            rewards[i] = _claimRewardToken(
                state[i].rewardToken,
                account,
                accountSharesBefore,
                accountSharesAfter,
                state[i].accumulatedRewardPerVaultShare
            );
        }
    }

    /// @notice Executes a claim against the given reward pool type and updates internal
    /// rewarder accumulators.
    function _claimVaultRewards(
        uint256 effectiveSupplyBefore,
        VaultRewardState[] memory state
    ) internal {
        RewardPoolStorage memory rewardPool = _getRewardPoolSlot();
        if (rewardPool.rewardPool == address(0)) return;
        if (block.timestamp < rewardPool.lastClaimTimestamp + rewardPool.forceClaimAfter) return;

        uint256[] memory balancesBefore = new uint256[](state.length);
        // Run a generic call against the reward pool and then do a balance
        // before and after check.
        for (uint256 i; i < state.length; i++) {
            // Presumes that ETH will never be given out as a reward token.
            balancesBefore[i] = ERC20(state[i].rewardToken).balanceOf(address(this));
        }

        _executeClaim();

        _getRewardPoolSlot().lastClaimTimestamp = uint32(block.timestamp);

        // This only accumulates rewards claimed, it does not accumulate any secondary emissions
        // that are streamed to vault users.
        for (uint256 i; i < state.length; i++) {
            uint256 balanceAfter = ERC20(state[i].rewardToken).balanceOf(address(this));
            _accumulateSecondaryRewardViaClaim(
                i,
                state[i],
                // balanceAfter should never be less than balanceBefore
                balanceAfter - balancesBefore[i],
                effectiveSupplyBefore
            );
        }
    }


    /** Reward Claim Methods **/

    function _claimRewardToken(
        address rewardToken,
        address account,
        uint256 accountSharesBefore,
        uint256 accountSharesAfter,
        uint256 rewardsPerVaultShare
    ) internal returns (uint256 rewardToClaim) {
        // Vault shares are always in DEFAULT_PRECISION
        uint256 rewardDebt = _getAccountRewardDebtSlot()[rewardToken][account];
        rewardToClaim = ((accountSharesBefore * rewardsPerVaultShare) / DEFAULT_PRECISION) - rewardDebt;
        _getAccountRewardDebtSlot()[rewardToken][account] = (
            (accountSharesAfter * rewardsPerVaultShare) / DEFAULT_PRECISION
        );

        if (0 < rewardToClaim) {
            // Ignore transfer errors here so that any strange failures here do not
            // prevent normal vault operations from working. Failures may include a
            // lack of balances or some sort of blacklist that prevents an account
            // from receiving tokens.
            if (rewardToken.code.length > 0) {
                try IEIP20NonStandard(rewardToken).transfer(account, rewardToClaim) {
                    bool success = TokenUtils.checkReturnCode();
                    if (success) {
                        emit VaultRewardTransfer(rewardToken, account, rewardToClaim);
                    } else {
                        emit VaultRewardTransfer(rewardToken, account, 0);
                    }
                // Emits zero tokens transferred if the transfer fails.
                } catch {
                    emit VaultRewardTransfer(rewardToken, account, 0);
                }
            }
        }
    }

    /*** ACCUMULATORS  ***/

    function _accumulateSecondaryRewardViaClaim(
        uint256 index,
        VaultRewardState memory state,
        uint256 tokensClaimed,
        uint256 effectiveSupplyBefore
    ) private {
        if (tokensClaimed == 0) return;

        state.accumulatedRewardPerVaultShare += (
            (tokensClaimed * DEFAULT_PRECISION) / effectiveSupplyBefore
        ).toUint128();

        _getVaultRewardStateSlot()[index] = state;
    }

    function _accumulateSecondaryRewardViaEmissionRate(
        uint256 index,
        VaultRewardState memory state,
        uint256 effectiveSupplyBefore
    ) private {
        state.accumulatedRewardPerVaultShare = _getAccumulatedRewardViaEmissionRate(
            state, effectiveSupplyBefore, block.timestamp
        ).toUint128();
        state.lastAccumulatedTime = uint32(block.timestamp);

        _getVaultRewardStateSlot()[index] = state;
    }

    function _getAccumulatedRewardViaEmissionRate(
        VaultRewardState memory state,
        uint256 effectiveSupplyBefore,
        uint256 blockTime
    ) private pure returns (uint256) {
        // Short circuit the method with no emission rate
        if (state.emissionRatePerYear == 0) return state.accumulatedRewardPerVaultShare;
        require(0 < state.endTime);
        uint256 time = blockTime < state.endTime ? blockTime : state.endTime;

        uint256 additionalIncentiveAccumulatedPerVaultShare;
        if (state.lastAccumulatedTime < time && 0 < effectiveSupplyBefore) {
            // NOTE: no underflow, checked in if statement
            uint256 timeSinceLastAccumulation = time - state.lastAccumulatedTime;
            // Precision here is:
            //  timeSinceLastAccumulation (SECONDS)
            //  emissionRatePerYear (REWARD_TOKEN_PRECISION)
            //  DEFAULT_PRECISION (1e18)
            // DIVIDE BY
            //  YEAR (SECONDS)
            //  DEFAULT_PRECISION (1e18)
            // => Precision = REWARD_TOKEN_PRECISION
            additionalIncentiveAccumulatedPerVaultShare = (timeSinceLastAccumulation * DEFAULT_PRECISION * state.emissionRatePerYear)
                / (YEAR * effectiveSupplyBefore);
        }

        return state.accumulatedRewardPerVaultShare + additionalIncentiveAccumulatedPerVaultShare;
    }

    /// @notice Executes the proper call for various rewarder types.
    function _executeClaim() internal virtual;
    function _withdrawFromPreviousRewardPool(RewardPoolStorage memory oldRewardPool) internal virtual;
    function _depositIntoNewRewardPool(address poolToken, uint256 poolTokens, RewardPoolStorage memory newRewardPool) internal virtual;
}