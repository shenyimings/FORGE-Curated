/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IProver} from "./interfaces/IProver.sol";
import {IIntentSource} from "./interfaces/IIntentSource.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPermit} from "./interfaces/IPermit.sol";

import {Intent, Route, Reward} from "./types/Intent.sol";
import {AddressConverter} from "./libs/AddressConverter.sol";
import {Refund} from "./libs/Refund.sol";

import {OriginSettler} from "./ERC7683/OriginSettler.sol";
import {Vault} from "./vault/Vault.sol";
import {Clones} from "./vault/Clones.sol";

/**
 * @title IntentSource
 * @notice Abstract contract for managing cross-chain intents and their associated rewards on the source chain
 * @dev Base contract containing all core intent functionality for EVM chains
 */
abstract contract IntentSource is OriginSettler, IIntentSource {
    using SafeERC20 for IERC20;
    using AddressConverter for address;
    using Clones for address;
    using Math for uint256;

    /// @dev CREATE2 prefix for deterministic address calculation (0xff standard, 0x41 TRON)
    bytes1 private immutable CREATE2_PREFIX;

    /// @dev Tron Mainnet chain ID
    uint256 private immutable TRON_MAINNET_CHAIN_ID = 728126428;
    /// @dev Tron Testnet (Shasta) chain ID
    uint256 private immutable TRON_TESTNET_CHAIN_ID = 2494104990;

    /// @dev Implementation contract address for vault cloning
    address private immutable VAULT_IMPLEMENTATION;
    /// @dev Tracks the lifecycle status of each intent's rewards
    mapping(bytes32 => Status) private rewardStatuses;

    /**
     * @notice Initializes the IntentSource contract
     * @dev Sets CREATE2 prefix based on chain ID and deploys vault implementation
     *      Uses TRON-specific prefix (0x41) for TRON networks, standard prefix (0xff) otherwise
     */
    constructor() {
        // TRON support
        CREATE2_PREFIX = block.chainid == TRON_MAINNET_CHAIN_ID ||
            block.chainid == TRON_TESTNET_CHAIN_ID
            ? bytes1(0x41) // TRON chain custom CREATE2 prefix
            : bytes1(0xff);

        VAULT_IMPLEMENTATION = address(new Vault());
    }

    /**
     * @notice Ensures intent can be funded based on its current status
     * @dev Prevents funding of intents that are already withdrawn or refunded
     *      Allows funding of Initial or Funded status intents (for partial funding)
     * @param intentHash Hash of the intent to validate for funding eligibility
     */
    modifier onlyFundable(bytes32 intentHash) {
        Status status = rewardStatuses[intentHash];

        if (status == Status.Withdrawn || status == Status.Refunded) {
            revert InvalidStatusForFunding(status);
        }

        if (status == Status.Funded) {
            return;
        }

        _;
    }

    /**
     * @notice Retrieves reward status for a given intent hash
     * @param intentHash Hash of the intent to query
     * @return status Current status of the intent
     */
    function getRewardStatus(
        bytes32 intentHash
    ) public view returns (Status status) {
        return rewardStatuses[intentHash];
    }

    /**
     * @notice Calculates the hash of an intent and its components
     * @param intent The intent to hash
     * @return intentHash Combined hash of route and reward
     * @return routeHash Hash of the route component
     * @return rewardHash Hash of the reward component
     */
    function getIntentHash(
        Intent memory intent
    )
        public
        pure
        returns (bytes32 intentHash, bytes32 routeHash, bytes32 rewardHash)
    {
        return
            getIntentHash(
                intent.destination,
                abi.encode(intent.route),
                intent.reward
            );
    }

    /**
     * @notice Calculates the hash of an intent and its components
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes for cross-VM compatibility
     * @param reward Reward structure containing distribution details
     * @return intentHash Combined hash of route and reward
     * @return routeHash Hash of the route component
     * @return rewardHash Hash of the reward component
     */
    function getIntentHash(
        uint64 destination,
        bytes memory route,
        Reward memory reward
    )
        public
        pure
        returns (bytes32 intentHash, bytes32 routeHash, bytes32 rewardHash)
    {
        (intentHash, routeHash, rewardHash) = getIntentHash(
            destination,
            keccak256(route),
            reward
        );
    }

    /**
     * @notice Calculates intent hash from route hash and reward components
     * @param destination Destination chain ID for the intent
     * @param _routeHash Pre-computed hash of the route component
     * @param reward Reward structure containing distribution details
     * @return intentHash Combined hash of route and reward
     * @return routeHash Hash of the route component (passed through)
     * @return rewardHash Hash of the reward component
     */
    function getIntentHash(
        uint64 destination,
        bytes32 _routeHash,
        Reward memory reward
    )
        public
        pure
        returns (bytes32 intentHash, bytes32 routeHash, bytes32 rewardHash)
    {
        routeHash = _routeHash;
        rewardHash = keccak256(abi.encode(reward));
        intentHash = keccak256(
            abi.encodePacked(destination, routeHash, rewardHash)
        );
    }

    /**
     * @notice Calculates the deterministic address of the intent vault
     * @param intent Intent to calculate vault address for
     * @return Address of the intent vault
     */
    function intentVaultAddress(
        Intent calldata intent
    ) public view returns (address) {
        return
            intentVaultAddress(
                intent.destination,
                abi.encode(intent.route),
                intent.reward
            );
    }

    /**
     * @notice Calculates the deterministic address of the intent vault
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @return Address of the intent vault
     */
    function intentVaultAddress(
        uint64 destination,
        bytes memory route,
        Reward calldata reward
    ) public view returns (address) {
        (bytes32 intentHash, , ) = getIntentHash(destination, route, reward);

        return _getVault(intentHash);
    }

    /**
     * @notice Checks if an intent is completely funded
     * @param intent Intent to validate
     * @return True if intent is completely funded, false otherwise
     */
    function isIntentFunded(Intent calldata intent) public view returns (bool) {
        return
            isIntentFunded(
                intent.destination,
                abi.encode(intent.route),
                intent.reward
            );
    }

    /**
     * @notice Checks if an intent is fully funded using universal format
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @return True if intent is completely funded, false otherwise
     */
    function isIntentFunded(
        uint64 destination,
        bytes memory route,
        Reward calldata reward
    ) public view returns (bool) {
        (bytes32 intentHash, , ) = getIntentHash(destination, route, reward);

        return
            rewardStatuses[intentHash] == Status.Funded ||
            _isRewardFunded(reward, _getVault(intentHash));
    }

    /**
     * @notice Creates an intent without funding
     * @param intent The complete intent struct to be published
     * @return intentHash Hash of the created intent
     * @return vault Address of the created vault
     */
    function publish(
        Intent calldata intent
    ) public returns (bytes32 intentHash, address vault) {
        return
            publish(
                intent.destination,
                abi.encode(intent.route),
                intent.reward
            );
    }

    /**
     * @notice Creates an intent without funding
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @return intentHash Hash of the created intent
     * @return vault Address of the created vault
     */
    function publish(
        uint64 destination,
        bytes memory route,
        Reward memory reward
    ) public returns (bytes32 intentHash, address vault) {
        (intentHash, , ) = getIntentHash(destination, route, reward);
        vault = _getVault(intentHash);

        _validatePublish(intentHash);
        _emitIntentPublished(intentHash, destination, route, reward);
    }

    /**
     * @notice Creates and funds an intent in a single transaction
     * @param intent The complete intent struct to be published and funded
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Hash of the created and funded intent
     * @return vault Address of the created vault
     */
    function publishAndFund(
        Intent calldata intent,
        bool allowPartial
    ) public payable returns (bytes32 intentHash, address vault) {
        return
            publishAndFund(
                intent.destination,
                abi.encode(intent.route),
                intent.reward,
                allowPartial
            );
    }

    /**
     * @notice Creates and funds an intent in a single transaction
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Hash of the created and funded intent
     * @return vault Address of the created vault
     */
    function publishAndFund(
        uint64 destination,
        bytes memory route,
        Reward calldata reward,
        bool allowPartial
    ) public payable returns (bytes32 intentHash, address vault) {
        return
            _publishAndFund(
                destination,
                route,
                reward,
                allowPartial,
                msg.sender
            );
    }

    /**
     * @notice Funds an existing intent
     * @param destination Destination chain ID for the intent
     * @param routeHash Hash of the route component
     * @param reward Reward structure containing distribution details
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Hash of the funded intent
     */
    function fund(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        bool allowPartial
    ) external payable returns (bytes32 intentHash) {
        (intentHash, , ) = getIntentHash(destination, routeHash, reward);

        _fundIntent(
            intentHash,
            _getVault(intentHash),
            reward,
            msg.sender,
            allowPartial
        );
        Refund.excessNative();
    }

    /**
     * @notice Funds an intent for a user with permit/allowance
     * @param destination Destination chain ID for the intent
     * @param routeHash Hash of the route component
     * @param reward Reward structure containing distribution details
     * @param funder Address to fund the intent from
     * @param permitContract Address of the permitContract instance
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Hash of the funded intent
     */
    function fundFor(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        bool allowPartial,
        address funder,
        address permitContract
    ) external payable returns (bytes32 intentHash) {
        (intentHash, , ) = getIntentHash(destination, routeHash, reward);

        _fundIntentFor(
            reward,
            intentHash,
            allowPartial,
            funder,
            permitContract
        );
    }

    /**
     * @notice Creates and funds an intent using permit/allowance
     * @param intent The complete intent struct
     * @param funder Address to fund the intent from
     * @param permitContract Address of the permitContract instance
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Hash of the created and funded intent
     */
    function publishAndFundFor(
        Intent calldata intent,
        bool allowPartial,
        address funder,
        address permitContract
    ) public payable returns (bytes32 intentHash, address vault) {
        return
            publishAndFundFor(
                intent.destination,
                abi.encode(intent.route),
                intent.reward,
                allowPartial,
                funder,
                permitContract
            );
    }

    /**
     * @notice Creates and funds an intent on behalf of another address using universal format
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @param funder The address providing the funding
     * @param permitContract The permit contract for token approvals
     * @param allowPartial Whether to accept partial funding
     * @return intentHash Hash of the created and funded intent
     * @return vault Address of the created vault
     */
    function publishAndFundFor(
        uint64 destination,
        bytes memory route,
        Reward calldata reward,
        bool allowPartial,
        address funder,
        address permitContract
    ) public payable returns (bytes32 intentHash, address vault) {
        (intentHash, ) = publish(destination, route, reward);

        vault = _fundIntentFor(
            reward,
            intentHash,
            allowPartial,
            funder,
            permitContract
        );
    }

    /**
     * @notice Withdraws rewards associated with an intent to its claimant
     * @param destination Destination chain ID for the intent
     * @param routeHash Hash of the intent's route
     * @param reward Reward structure of the intent
     */
    function withdraw(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward
    ) public {
        (bytes32 intentHash, , bytes32 rewardHash) = getIntentHash(
            destination,
            routeHash,
            reward
        );

        IProver.ProofData memory proof = IProver(reward.prover).provenIntents(
            intentHash
        );
        address claimant = proof.claimant;

        // If the intent has been proven on a different chain, challenge the proof
        if (proof.destination != destination && claimant != address(0)) {
            // Challenge the proof and emit event
            IProver(reward.prover).challengeIntentProof(
                destination,
                routeHash,
                rewardHash
            );

            return;
        }

        _validateWithdraw(intentHash, claimant);
        rewardStatuses[intentHash] = Status.Withdrawn;

        IVault vault = IVault(_getOrDeployVault(intentHash));
        vault.withdraw(reward, claimant);

        emit IntentWithdrawn(intentHash, claimant);
    }

    /**
     * @notice Batch withdraws multiple intents
     * @param destinations Array of destination chain IDs for the intents
     * @param routeHashes Array of route hashes for the intents
     * @param rewards Array of reward structures for the intents
     */
    function batchWithdraw(
        uint64[] calldata destinations,
        bytes32[] calldata routeHashes,
        Reward[] calldata rewards
    ) external {
        uint256 length = routeHashes.length;

        if (length != rewards.length || length != destinations.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < length; ++i) {
            withdraw(destinations[i], routeHashes[i], rewards[i]);
        }
    }

    /**
     * @notice Refunds rewards to the intent creator
     * @param destination Destination chain ID for the intent
     * @param routeHash Hash of the intent's route
     * @param reward Reward structure of the intent
     */
    function refund(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward
    ) external {
        (bytes32 intentHash, , ) = getIntentHash(
            destination,
            routeHash,
            reward
        );

        _refund(intentHash, destination, reward, reward.creator);
    }

    /**
     * @notice Refunds rewards to a specified address (only callable by reward creator)
     * @param destination Destination chain ID for the intent
     * @param routeHash Hash of the intent's route
     * @param reward Reward structure of the intent
     * @param refundee Address to receive the refunded rewards
     */
    function refundTo(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        address refundee
    ) external {
        if (msg.sender != reward.creator) {
            revert NotCreatorCaller(msg.sender);
        }

        (bytes32 intentHash, , ) = getIntentHash(
            destination,
            routeHash,
            reward
        );

        _refund(intentHash, destination, reward, refundee);
    }

    /**
     * @notice Recover tokens that were sent to the intent vault by mistake
     * @dev Must not be among the intent's rewards
     * @param destination Destination chain ID for the intent
     * @param routeHash Hash of the intent's route
     * @param reward Reward structure of the intent
     * @param token Token address for handling incorrect vault transfers
     */
    function recoverToken(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        address token
    ) external {
        (bytes32 intentHash, , ) = getIntentHash(
            destination,
            routeHash,
            reward
        );

        _validateRecover(reward, token);

        IVault vault = IVault(_getOrDeployVault(intentHash));
        vault.recover(reward.creator, token);

        emit IntentTokenRecovered(intentHash, reward.creator, token);
    }

    /**
     * @notice Separate function to emit the IntentPublished event
     * @dev This helps avoid stack-too-deep errors in the calling function
     * @param intentHash Hash of the intent
     * @param destination Destination chain ID
     * @param route Encoded route data
     * @param reward Reward specification
     */
    function _emitIntentPublished(
        bytes32 intentHash,
        uint64 destination,
        bytes memory route,
        Reward memory reward
    ) internal {
        emit IntentPublished(
            intentHash,
            destination,
            route,
            reward.creator,
            reward.prover,
            reward.deadline,
            reward.nativeAmount,
            reward.tokens
        );
    }

    /**
     * @notice Core OriginSettler implementation for atomic intent creation and funding
     * @dev Implements the unified _publishAndFund method for both open() and openFor()
     * @dev Provides replay protection through vault state checking in funding logic
     * @dev Handles excess ETH return for optimal user experience
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @param allowPartial Whether to accept partial funding
     * @param funder The address providing the funding
     * @return intentHash Hash of the created and funded intent
     * @return vault Address of the created vault
     */
    function _publishAndFund(
        uint64 destination,
        bytes memory route,
        Reward memory reward,
        bool allowPartial,
        address funder
    ) internal override returns (bytes32 intentHash, address vault) {
        (intentHash, vault) = publish(destination, route, reward);

        _fundIntent(intentHash, vault, reward, funder, allowPartial);
        Refund.excessNative();
    }

    /**
     * @notice Handles the funding of an intent - OriginSettler implementation
     * @dev Called by _publishAndFund to atomically fund intents after creation
     * @dev Updates reward status and validates funding completeness
     * @param intentHash Hash of the intent
     * @param vault Address of the intent's vault
     * @param reward Reward structure to fund
     * @param funder Address providing the funds
     * @param allowPartial Whether to allow partial funding
     */
    function _fundIntent(
        bytes32 intentHash,
        address vault,
        Reward memory reward,
        address funder,
        bool allowPartial
    ) internal onlyFundable(intentHash) {
        bool fullyFunded = _fundNative(vault, reward.nativeAmount);

        uint256 rewardsLength = reward.tokens.length;
        for (uint256 i; i < rewardsLength; ++i) {
            IERC20 token = IERC20(reward.tokens[i].token);

            fullyFunded =
                fullyFunded &&
                _fundToken(vault, funder, token, reward.tokens[i].amount);
        }

        if (!allowPartial && !fullyFunded) {
            revert InsufficientFunds(intentHash);
        }

        if (fullyFunded) {
            rewardStatuses[intentHash] = Status.Funded;
        }

        emit IntentFunded(intentHash, funder, fullyFunded);
    }

    /**
     * @notice Funds vault with native tokens (ETH)
     * @param vault Address of the vault to fund
     * @param rewardAmount Required native token amount
     * @return funded True if vault has sufficient native balance after funding attempt
     */
    function _fundNative(
        address vault,
        uint256 rewardAmount
    ) internal returns (bool funded) {
        uint256 balance = vault.balance;

        if (balance >= rewardAmount) {
            return true;
        }

        uint256 remaining = rewardAmount - balance;
        uint256 transferAmount = remaining.min(msg.value);

        if (transferAmount > 0) {
            payable(vault).transfer(transferAmount);
        }

        return transferAmount >= remaining;
    }

    /**
     * @notice Funds vault with ERC20 tokens
     * @param vault Address of the vault to fund
     * @param token ERC20 token contract to transfer
     * @param rewardAmount Required token amount
     * @return funded True if vault has sufficient token balance after funding attempt
     */
    function _fundToken(
        address vault,
        address funder,
        IERC20 token,
        uint256 rewardAmount
    ) internal returns (bool funded) {
        uint256 balance = token.balanceOf(vault);

        if (balance >= rewardAmount) {
            return true;
        }

        uint256 remaining = rewardAmount - balance;
        uint256 transferAmount = remaining
            .min(token.allowance(funder, address(this)))
            .min(token.balanceOf(funder));

        if (transferAmount > 0) {
            token.safeTransferFrom(funder, vault, transferAmount);
        }

        return balance + transferAmount >= rewardAmount;
    }

    /**
     * @notice Funds an intent using a permit contract for gasless approvals
     * @param reward Reward structure containing funding requirements
     * @param intentHash Hash of the intent to fund
     * @param funder Address providing the funding
     * @param permitContract Address of permit contract for token approvals
     * @param allowPartial Whether to allow partial funding
     * @return vault Address of the funded vault
     */
    function _fundIntentFor(
        Reward calldata reward,
        bytes32 intentHash,
        bool allowPartial,
        address funder,
        address permitContract
    ) internal onlyFundable(intentHash) returns (address vault) {
        vault = _getOrDeployVault(intentHash);
        bool fullyFunded = IVault(vault).fundFor{value: msg.value}(
            reward,
            funder,
            IPermit(permitContract)
        );

        if (!allowPartial && !fullyFunded) {
            revert InsufficientFunds(intentHash);
        }

        if (fullyFunded) {
            rewardStatuses[intentHash] = Status.Funded;
        }

        emit IntentFunded(intentHash, funder, fullyFunded);
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

        if (vault.balance < reward.nativeAmount) return false;

        for (uint256 i = 0; i < rewardsLength; ++i) {
            address token = reward.tokens[i].token;
            uint256 amount = reward.tokens[i].amount;
            uint256 balance = IERC20(token).balanceOf(vault);

            if (balance < amount) return false;
        }

        return true;
    }

    /**
     * @notice Validates and publishes a new intent
     * @param intentHash Hash of the intent
     */
    function _validatePublish(bytes32 intentHash) internal view {
        Status status = rewardStatuses[intentHash];

        if (status == Status.Withdrawn || status == Status.Refunded) {
            revert IntentAlreadyExists(intentHash);
        }
    }

    /**
     * @notice Validates that an intent can be refunded
     * @dev Checks if intent has been proven/claimed to prevent invalid refunds
     * @param intentHash Hash of the intent to validate
     * @param destination Expected destination chain ID
     * @param reward Reward structure containing prover information
     */
    function _validateRefund(
        bytes32 intentHash,
        uint64 destination,
        Reward calldata reward
    ) internal view {
        Status status = rewardStatuses[intentHash];
        IProver.ProofData memory proof = IProver(reward.prover).provenIntents(
            intentHash
        );

        // If proof is incorrect or no proof
        if (proof.destination != destination || proof.claimant == address(0)) {
            if (block.timestamp < reward.deadline) {
                revert InvalidStatusForRefund(
                    status,
                    block.timestamp,
                    reward.deadline
                );
            }

            return;
        }

        if (status == Status.Initial || status == Status.Funded) {
            revert IntentNotClaimed(intentHash);
        }
    }

    /**
     * @notice Validates that vault can be withdrawn from and claimant is valid
     * @dev Allows withdrawal from Initial or Funded status, prevents zero address claimant
     * @param intentHash Hash of the intent
     * @param claimant Address that will receive the withdrawn rewards
     */
    function _validateWithdraw(
        bytes32 intentHash,
        address claimant
    ) internal view {
        Status status = rewardStatuses[intentHash];

        if (status != Status.Initial && status != Status.Funded) {
            revert InvalidStatusForWithdrawal(status);
        }

        if (claimant == address(0)) {
            revert InvalidClaimant();
        }
    }

    /**
     * @notice Validates that token can be recovered (not zero address and not a reward token)
     * @dev Prevents recovery of reward tokens and zero address, allows recovery of mistaken transfers
     * @param reward Reward structure containing token list
     * @param token Address of the token to recover
     */
    function _validateRecover(
        Reward calldata reward,
        address token
    ) internal pure {
        if (token == address(0)) {
            revert InvalidRecoverToken(token);
        }

        uint256 rewardsLength = reward.tokens.length;
        for (uint256 i; i < rewardsLength; ++i) {
            if (reward.tokens[i].token == token) {
                revert InvalidRecoverToken(token);
            }
        }
    }

    /**
     * @notice Internal function to refund rewards to a specified address
     * @param intentHash Hash of the intent to refund
     * @param destination Destination chain ID for the intent
     * @param reward Reward structure of the intent
     * @param refundee Address to receive the refunded rewards
     */
    function _refund(
        bytes32 intentHash,
        uint64 destination,
        Reward calldata reward,
        address refundee
    ) internal {
        _validateRefund(intentHash, destination, reward);
        rewardStatuses[intentHash] = Status.Refunded;

        IVault vault = IVault(_getOrDeployVault(intentHash));
        vault.refund(reward, refundee);

        emit IntentRefunded(intentHash, refundee);
    }

    /**
     * @notice Gets existing vault address or deploys new one if needed
     * @param intentHash Hash used as CREATE2 salt for deterministic addressing
     * @return Address of the vault (existing or newly deployed)
     */
    function _getOrDeployVault(bytes32 intentHash) internal returns (address) {
        address vault = _getVault(intentHash);

        return
            vault.code.length > 0
                ? vault
                : VAULT_IMPLEMENTATION.clone(intentHash);
    }

    /**
     * @notice Calculates the deterministic vault address without deployment
     * @param intentHash Hash used as CREATE2 salt for address calculation
     * @return Predicted address of the vault
     */
    function _getVault(bytes32 intentHash) internal view returns (address) {
        return VAULT_IMPLEMENTATION.predict(intentHash, CREATE2_PREFIX);
    }
}
