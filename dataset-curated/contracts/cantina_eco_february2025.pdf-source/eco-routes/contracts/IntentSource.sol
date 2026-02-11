/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IIntentSource} from "./interfaces/IIntentSource.sol";
import {BaseProver} from "./prover/BaseProver.sol";
import {Intent, Route, Reward, Call} from "./types/Intent.sol";
import {Semver} from "./libs/Semver.sol";

import {Vault} from "./Vault.sol";

/**
 * @title IntentSource
 * @notice Source chain contract for the Eco Protocol's intent system
 * @dev Used to create intents and withdraw associated rewards. Works in conjunction with
 *      an inbox contract on the destination chain. Verifies intent fulfillment through
 *      a prover contract on the source chain
 * @dev This contract should not hold any funds or hold any roles for other contracts,
 *      as it executes arbitrary calls to other contracts when funding intents.
 */
contract IntentSource is IIntentSource, Semver {
    using SafeERC20 for IERC20;

    mapping(bytes32 intentHash => VaultStorage) public vaults;

    constructor() {}

    /**
     * @notice Retrieves reward status for a given intent hash
     * @param intentHash Hash of the intent to query
     * @return status Current status of the intent
     */
    function getRewardStatus(
        bytes32 intentHash
    ) external view returns (RewardStatus status) {
        return RewardStatus(vaults[intentHash].state.status);
    }

    /**
     * @notice Retrieves vault state for a given intent hash
     * @param intentHash Hash of the intent to query
     * @return VaultState struct containing vault information
     */
    function getVaultState(
        bytes32 intentHash
    ) external view returns (VaultState memory) {
        return vaults[intentHash].state;
    }

    /**
     * @notice Retrieves the permitContact address funding an intent
     */
    function getPermitContract(
        bytes32 intentHash
    ) external view returns (address) {
        return vaults[intentHash].permitContract;
    }

    /**
     * @notice Calculates the hash of an intent and its components
     * @param intent The intent to hash
     * @return intentHash Combined hash of route and reward
     * @return routeHash Hash of the route component
     * @return rewardHash Hash of the reward component
     */
    function getIntentHash(
        Intent calldata intent
    )
        public
        pure
        returns (bytes32 intentHash, bytes32 routeHash, bytes32 rewardHash)
    {
        routeHash = keccak256(abi.encode(intent.route));
        rewardHash = keccak256(abi.encode(intent.reward));
        intentHash = keccak256(abi.encodePacked(routeHash, rewardHash));
    }

    /**
     * @notice Calculates the deterministic address of the intent vault
     * @param intent Intent to calculate vault address for
     * @return Address of the intent vault
     */
    function intentVaultAddress(
        Intent calldata intent
    ) external view returns (address) {
        (bytes32 intentHash, bytes32 routeHash, ) = getIntentHash(intent);
        return _getIntentVaultAddress(intentHash, routeHash, intent.reward);
    }

    /**
     * @notice Creates an intent without funding
     * @param intent The complete intent struct to be published
     * @return intentHash Hash of the created intent
     */
    function publish(
        Intent calldata intent
    ) external returns (bytes32 intentHash) {
        (intentHash, , ) = getIntentHash(intent);
        VaultState memory state = vaults[intentHash].state;

        _validateAndPublishIntent(intent, intentHash, state);
    }

    /**
     * @notice Creates and funds an intent in a single transaction
     * @param intent The complete intent struct to be published and funded
     * @return intentHash Hash of the created and funded intent
     */
    function publishAndFund(
        Intent calldata intent
    ) external payable returns (bytes32 intentHash) {
        bytes32 routeHash;
        (intentHash, routeHash, ) = getIntentHash(intent);
        VaultState memory state = vaults[intentHash].state;

        _validateInitialFundingState(state, intentHash);
        _validateSourceChain(intent.route.source, intentHash);
        _validateAndPublishIntent(intent, intentHash, state);

        address vault = _getIntentVaultAddress(
            intentHash,
            routeHash,
            intent.reward
        );
        _fundIntent(intentHash, intent.reward, vault, msg.sender);

        _returnExcessEth(intentHash, address(this).balance);
    }

    /**
     * @notice Funds an existing intent
     * @param routeHash Hash of the route component
     * @param reward Reward structure containing distribution details
     * @return intentHash Hash of the funded intent
     */
    function fund(
        bytes32 routeHash,
        Reward calldata reward
    ) external payable returns (bytes32 intentHash) {
        bytes32 rewardHash = keccak256(abi.encode(reward));
        intentHash = keccak256(abi.encodePacked(routeHash, rewardHash));
        VaultState memory state = vaults[intentHash].state;

        _validateInitialFundingState(state, intentHash);

        address vault = _getIntentVaultAddress(intentHash, routeHash, reward);
        _fundIntent(intentHash, reward, vault, msg.sender);
    }

    /**
     * @notice Funds an intent for a user with allowance/permit
     * @param routeHash Hash of the route component
     * @param reward Reward structure containing distribution details
     * @param funder Address to fund the intent from
     * @param permitContact Address of the permitContact instance
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Hash of the funded intent
     */
    function fundFor(
        bytes32 routeHash,
        Reward calldata reward,
        address funder,
        address permitContact,
        bool allowPartial
    ) external returns (bytes32 intentHash) {
        bytes32 rewardHash = keccak256(abi.encode(reward));
        intentHash = keccak256(abi.encodePacked(routeHash, rewardHash));
        VaultState memory state = vaults[intentHash].state;

        address vault = _getIntentVaultAddress(intentHash, routeHash, reward);

        _fundIntentFor(
            state,
            reward,
            intentHash,
            routeHash,
            vault,
            funder,
            permitContact,
            allowPartial
        );
    }

    /**
     * @notice Creates and funds an intent using permit/allowance
     * @param intent The complete intent struct
     * @return intentHash Hash of the created and funded intent
     */
    function publishAndFundFor(
        Intent calldata intent,
        address funder,
        address permitContact,
        bool allowPartial
    ) external returns (bytes32 intentHash) {
        bytes32 routeHash;
        (intentHash, routeHash, ) = getIntentHash(intent);
        VaultState memory state = vaults[intentHash].state;

        _validateAndPublishIntent(intent, intentHash, state);
        _validateSourceChain(intent.route.source, intentHash);

        address vault = _getIntentVaultAddress(
            intentHash,
            routeHash,
            intent.reward
        );

        _fundIntentFor(
            state,
            intent.reward,
            intentHash,
            routeHash,
            vault,
            funder,
            permitContact,
            allowPartial
        );
    }

    /**
     * @notice Checks if an intent is properly funded
     * @param intent Intent to validate
     * @return True if intent is properly funded, false otherwise
     */
    function isIntentFunded(
        Intent calldata intent
    ) external view returns (bool) {
        if (intent.route.source != block.chainid) return false;

        (bytes32 intentHash, bytes32 routeHash, ) = getIntentHash(intent);
        address vault = _getIntentVaultAddress(
            intentHash,
            routeHash,
            intent.reward
        );

        return _isRewardFunded(intent.reward, vault);
    }

    /**
     * @notice Withdraws rewards associated with an intent to its claimant
     * @param routeHash Hash of the intent's route
     * @param reward Reward structure of the intent
     */
    function withdrawRewards(bytes32 routeHash, Reward calldata reward) public {
        bytes32 rewardHash = keccak256(abi.encode(reward));
        bytes32 intentHash = keccak256(abi.encodePacked(routeHash, rewardHash));

        address claimant = BaseProver(reward.prover).provenIntents(intentHash);
        VaultState memory state = vaults[intentHash].state;

        // Claim the rewards if the intent has not been claimed
        if (
            claimant != address(0) &&
            state.status != uint8(RewardStatus.Claimed) &&
            state.status != uint8(RewardStatus.Refunded)
        ) {
            state.status = uint8(RewardStatus.Claimed);
            state.mode = uint8(VaultMode.Claim);
            state.allowPartialFunding = 0;
            state.usePermit = 0;
            state.target = claimant;
            vaults[intentHash].state = state;

            emit Withdrawal(intentHash, claimant);

            new Vault{salt: routeHash}(intentHash, reward);

            return;
        }

        if (claimant == address(0)) {
            revert UnauthorizedWithdrawal(intentHash);
        } else {
            revert RewardsAlreadyWithdrawn(intentHash);
        }
    }

    /**
     * @notice Batch withdraws multiple intents
     * @param routeHashes Array of route hashes for the intents
     * @param rewards Array of reward structures for the intents
     */
    function batchWithdraw(
        bytes32[] calldata routeHashes,
        Reward[] calldata rewards
    ) external {
        uint256 length = routeHashes.length;

        if (length != rewards.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < length; ++i) {
            withdrawRewards(routeHashes[i], rewards[i]);
        }
    }

    /**
     * @notice Refunds rewards to the intent creator
     * @param routeHash Hash of the intent's route
     * @param reward Reward structure of the intent
     */
    function refund(bytes32 routeHash, Reward calldata reward) external {
        bytes32 rewardHash = keccak256(abi.encode(reward));
        bytes32 intentHash = keccak256(abi.encodePacked(routeHash, rewardHash));

        VaultState memory state = vaults[intentHash].state;

        if (
            state.status != uint8(RewardStatus.Claimed) &&
            state.status != uint8(RewardStatus.Refunded) &&
            block.timestamp <= reward.deadline
        ) {
            revert IntentNotExpired(intentHash);
        }

        if (state.status != uint8(RewardStatus.Claimed)) {
            state.status = uint8(RewardStatus.Refunded);
        }

        state.mode = uint8(VaultMode.Refund);
        state.allowPartialFunding = 0;
        state.usePermit = 0;
        state.target = address(0);
        vaults[intentHash].state = state;

        emit Refund(intentHash, reward.creator);

        new Vault{salt: routeHash}(intentHash, reward);
    }

    /**
     * @notice Recover tokens that were sent to the intent vault by mistake
     * @dev Must not be among the intent's rewards
     * @param routeHash Hash of the intent's route
     * @param reward Reward structure of the intent
     * @param token Optional token address for handling incorrect vault transfers
     */
    function recoverToken(
        bytes32 routeHash,
        Reward calldata reward,
        address token
    ) external {
        if (token == address(0)) {
            revert InvalidRefundToken();
        }

        bytes32 rewardHash = keccak256(abi.encode(reward));
        bytes32 intentHash = keccak256(abi.encodePacked(routeHash, rewardHash));

        VaultState memory state = vaults[intentHash].state;

        // selfdestruct() will refund all native tokens to the creator
        // we can't refund native intents before the claim/refund happens
        // because deploying and destructing the vault will refund the native reward prematurely
        if (
            state.status != uint8(RewardStatus.Claimed) &&
            state.status != uint8(RewardStatus.Refunded) &&
            reward.nativeValue > 0
        ) {
            revert IntentNotClaimed(intentHash);
        }

        // Check if the token is part of the reward
        for (uint256 i = 0; i < reward.tokens.length; ++i) {
            if (reward.tokens[i].token == token) {
                revert InvalidRefundToken();
            }
        }

        state.mode = uint8(VaultMode.RecoverToken);
        state.allowPartialFunding = 0;
        state.usePermit = 0;
        state.target = token;
        vaults[intentHash].state = state;

        emit Refund(intentHash, reward.creator);

        new Vault{salt: routeHash}(intentHash, reward);
    }

    /**
     * @notice Validates that an intent's vault holds sufficient rewards
     * @dev Checks both native token and ERC20 token balances
     * @param reward Reward to validate
     * @param vault Address of the intent's vault
     * @return True if vault has sufficient funds, false otherwise
     */
    function _isRewardFunded(
        Reward calldata reward,
        address vault
    ) internal view returns (bool) {
        uint256 rewardsLength = reward.tokens.length;

        if (vault.balance < reward.nativeValue) return false;

        for (uint256 i = 0; i < rewardsLength; ++i) {
            address token = reward.tokens[i].token;
            uint256 amount = reward.tokens[i].amount;
            uint256 balance = IERC20(token).balanceOf(vault);

            if (balance < amount) return false;
        }

        return true;
    }

    /**
     * @notice Calculates the deterministic address of an intent vault using CREATE2
     * @dev Follows EIP-1014 for address calculation
     * @param intentHash Hash of the full intent
     * @param routeHash Hash of the route component
     * @param reward Reward structure
     * @return The calculated vault address
     */
    function _getIntentVaultAddress(
        bytes32 intentHash,
        bytes32 routeHash,
        Reward calldata reward
    ) internal view returns (address) {
        /* Convert a hash which is bytes32 to an address which is 20-byte long
        according to https://docs.soliditylang.org/en/v0.8.9/control-structures.html?highlight=create2#salted-contract-creations-create2 */
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                address(this),
                                routeHash,
                                keccak256(
                                    abi.encodePacked(
                                        type(Vault).creationCode,
                                        abi.encode(intentHash, reward)
                                    )
                                )
                            )
                        )
                    )
                )
            );
    }

    /**
     * @notice Validates and publishes a new intent
     * @param intent The intent to validate and publish
     * @param intentHash Hash of the intent
     * @param state Current vault state
     */
    function _validateAndPublishIntent(
        Intent calldata intent,
        bytes32 intentHash,
        VaultState memory state
    ) internal {
        if (
            state.status == uint8(RewardStatus.Claimed) ||
            state.status == uint8(RewardStatus.Refunded)
        ) {
            revert IntentAlreadyExists(intentHash);
        }

        emit IntentCreated(
            intentHash,
            intent.route.salt,
            intent.route.source,
            intent.route.destination,
            intent.route.inbox,
            intent.route.tokens,
            intent.route.calls,
            intent.reward.creator,
            intent.reward.prover,
            intent.reward.deadline,
            intent.reward.nativeValue,
            intent.reward.tokens
        );
    }

    /**
     * @notice Disabling fundFor for native intents
     * @dev Deploying vault in Fund mode might cause a loss of native reward
     * @param reward Reward structure to validate
     * @param vault Address of the intent vault
     * @param intentHash Hash of the intent
     */
    function _disableNativeReward(
        Reward calldata reward,
        address vault,
        bytes32 intentHash
    ) internal view {
        // selfdestruct() will refund all native tokens to the creator
        // we can't use Fund mode for intents with native value
        // because deploying and destructing the vault will refund the native reward prematurely
        if (reward.nativeValue > 0 && vault.balance > 0) {
            revert CannotFundForWithNativeReward(intentHash);
        }
    }

    /**
     * @notice Validates the initial funding state
     * @param state Current vault state
     * @param intentHash Hash of the intent
     */
    function _validateInitialFundingState(
        VaultState memory state,
        bytes32 intentHash
    ) internal pure {
        if (state.status != uint8(RewardStatus.Initial)) {
            revert IntentAlreadyFunded(intentHash);
        }
    }

    /**
     * @notice Validates the funding state for partial funding
     * @param state Current vault state
     * @param intentHash Hash of the intent
     */
    function _validateFundingState(
        VaultState memory state,
        bytes32 intentHash
    ) internal pure {
        if (
            state.status != uint8(RewardStatus.Initial) &&
            state.status != uint8(RewardStatus.PartiallyFunded)
        ) {
            revert IntentAlreadyFunded(intentHash);
        }
    }

    /**
     * @notice Handles the funding of an intent
     * @param intentHash Hash of the intent
     * @param reward Reward structure to fund
     * @param vault Address of the intent vault
     * @param funder Address providing the funds
     */
    function _fundIntent(
        bytes32 intentHash,
        Reward calldata reward,
        address vault,
        address funder
    ) internal {
        emit IntentFunded(intentHash, msg.sender);

        if (reward.nativeValue > 0) {
            if (msg.value < reward.nativeValue) {
                revert InsufficientNativeReward(intentHash);
            }
            payable(vault).transfer(reward.nativeValue);
        }

        for (uint256 i = 0; i < reward.tokens.length; ++i) {
            IERC20(reward.tokens[i].token).safeTransferFrom(
                funder,
                vault,
                reward.tokens[i].amount
            );
        }
    }

    function _fundIntentFor(
        VaultState memory state,
        Reward calldata reward,
        bytes32 intentHash,
        bytes32 routeHash,
        address vault,
        address funder,
        address permitContact,
        bool allowPartial
    ) internal {
        _disableNativeReward(reward, vault, intentHash);
        _validateFundingState(state, intentHash);

        if (state.status == uint8(RewardStatus.Initial)) {
            state.status = allowPartial
                ? uint8(RewardStatus.PartiallyFunded)
                : uint8(RewardStatus.Funded);
        }

        state.mode = uint8(VaultMode.Fund);
        state.allowPartialFunding = allowPartial ? 1 : 0;
        state.usePermit = permitContact != address(0) ? 1 : 0;
        state.target = funder;

        if (permitContact != address(0)) {
            vaults[intentHash].permitContract = permitContact;
        }

        vaults[intentHash].state = state;

        new Vault{salt: routeHash}(intentHash, reward);

        if (state.status == uint8(RewardStatus.Funded)) {
            emit IntentFunded(intentHash, funder);
        } else if (
            state.status == uint8(RewardStatus.PartiallyFunded) &&
            _isRewardFunded(reward, vault)
        ) {
            state.status = uint8(RewardStatus.Funded);
            vaults[intentHash].state = state;

            emit IntentFunded(intentHash, funder);
        } else {
            emit IntentPartiallyFunded(intentHash, funder);
        }
    }

    /**
     * @notice Validates that the intent is being published on correct chain
     * @param sourceChain Chain ID specified in the intent
     * @param intentHash Hash of the intent
     */
    function _validateSourceChain(
        uint256 sourceChain,
        bytes32 intentHash
    ) internal view {
        if (sourceChain != block.chainid) {
            revert WrongSourceChain(intentHash);
        }
    }

    /**
     * @notice Returns excess ETH to the sender
     * @param intentHash Hash of the intent
     * @param amount Amount of ETH to return
     */
    function _returnExcessEth(bytes32 intentHash, uint256 amount) internal {
        if (amount > 0) {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert NativeRewardTransferFailed(intentHash);
        }
    }
}
