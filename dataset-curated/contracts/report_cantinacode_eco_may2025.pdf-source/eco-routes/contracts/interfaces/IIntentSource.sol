/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Intent, Reward, TokenAmount} from "../types/Intent.sol";

/**
 * @title IIntentSource
 * @notice Interface for managing cross-chain intents and their associated rewards on the source chain
 * @dev This contract works in conjunction with a portal contract on the destination chain
 *      and a prover contract for verification. It handles intent creation, funding,
 *      and reward distribution.
 */
interface IIntentSource {
    /// @notice Intent lifecycle status
    enum Status {
        Initial, /// @dev Intent created, may be partially funded but not fully funded
        Funded, /// @dev Intent has been fully funded with all required rewards
        Withdrawn, /// @dev Rewards have been withdrawn by claimant
        Refunded /// @dev Rewards have been refunded to creator
    }

    /**
     * @notice Indicates an attempt to publish a duplicate intent
     * @param intentHash The hash of the pre-existing intent
     */
    error IntentAlreadyExists(bytes32 intentHash);

    /**
     * @notice Indicates a premature refund attempt before intent completion
     * @param intentHash The hash of the unclaimed intent
     */
    error IntentNotClaimed(bytes32 intentHash);

    /**
     * @notice Indicates mismatched array lengths in batch operations
     */
    error ArrayLengthMismatch();

    /**
     * @notice Indicates insufficient funds to complete the intent funding
     * @param intentHash The hash of the intent that couldn't be funded
     */
    error InsufficientFunds(bytes32 intentHash);

    /// @notice Thrown when intent status is invalid for funding operation
    error InvalidStatusForFunding(Status status);

    /// @notice Thrown when intent status is invalid for withdrawal operation
    error InvalidStatusForWithdrawal(Status status);

    /// @notice Thrown when attempting to recover an invalid token (zero address or reward token)
    error InvalidRecoverToken(address token);

    /// @notice Thrown when intent status is invalid for refund operation or deadline not reached
    error InvalidStatusForRefund(
        Status status,
        uint256 currentTime,
        uint256 deadline
    );

    /// @notice Thrown when claimant address is address zero
    error InvalidClaimant();

    /// @notice Thrown when caller is not the reward creator
    error NotCreatorCaller(address caller);

    /**
     * @notice Signals the creation of a new cross-chain intent
     * @param intentHash Unique identifier of the intent
     * @param destination Destination chain ID
     * @param route Encoded route data for the destination chain
     * @param creator Intent originator address
     * @param prover Prover contract address
     * @param rewardDeadline Timestamp for reward claim eligibility
     * @param rewardNativeAmount Native token reward amount
     * @param rewardTokens ERC20 token rewards with amounts
     */
    event IntentPublished(
        bytes32 indexed intentHash,
        uint64 destination,
        bytes route,
        address indexed creator,
        address indexed prover,
        uint64 rewardDeadline,
        uint256 rewardNativeAmount,
        TokenAmount[] rewardTokens
    );

    /**
     * @notice Signals funding of an intent
     * @param intentHash The hash of the funded intent
     * @param funder The address providing the funding
     * @param complete Whether the intent was completely funded (true) or partially funded (false)
     */
    event IntentFunded(bytes32 intentHash, address funder, bool complete);

    /**
     * @notice Signals successful reward withdrawal
     * @param intentHash The hash of the claimed intent
     * @param claimant The address receiving the rewards
     */
    event IntentWithdrawn(bytes32 intentHash, address indexed claimant);

    /**
     * @notice Signals successful reward refund
     * @param intentHash The hash of the refunded intent
     * @param refundee The address receiving the refund
     */
    event IntentRefunded(bytes32 intentHash, address indexed refundee);

    /**
     * @notice Signals successful token recovery from an intent vault
     * @dev Emitted when tokens that were accidentally sent to a vault are recovered
     *      Only tokens not part of the intent's reward structure can be recovered
     * @param intentHash The hash of the intent whose vault had tokens recovered
     * @param refundee The address receiving the recovered tokens (typically the intent creator)
     * @param token The address of the token contract that was recovered
     */
    event IntentTokenRecovered(
        bytes32 intentHash,
        address indexed refundee,
        address indexed token
    );

    /**
     * @notice Retrieves the current reward claim status for an intent
     * @param intentHash The hash of the intent
     * @return status Current reward status
     */
    function getRewardStatus(
        bytes32 intentHash
    ) external view returns (Status status);

    /**
     * @notice Computes the hash components of an intent
     * @param intent The intent to hash
     * @return intentHash Combined hash of route and reward components
     * @return routeHash Hash of the route specifications
     * @return rewardHash Hash of the reward specifications
     */
    function getIntentHash(
        Intent memory intent
    )
        external
        pure
        returns (bytes32 intentHash, bytes32 routeHash, bytes32 rewardHash);

    /**
     * @notice Computes the hash components of an intent
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @return intentHash Combined hash of route and reward components
     * @return routeHash Hash of the route specifications
     * @return rewardHash Hash of the reward specifications
     */
    function getIntentHash(
        uint64 destination,
        bytes memory route,
        Reward memory reward
    )
        external
        pure
        returns (bytes32 intentHash, bytes32 routeHash, bytes32 rewardHash);

    /**
     * @notice Computes the deterministic vault address for an intent
     * @param intent The intent to calculate the vault address for
     * @return Predicted vault address
     */
    function intentVaultAddress(
        Intent calldata intent
    ) external view returns (address);

    /**
     * @notice Computes the deterministic vault address for an intent
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @return Predicted vault address
     */
    function intentVaultAddress(
        uint64 destination,
        bytes memory route,
        Reward calldata reward
    ) external view returns (address);

    /**
     * @notice Checks if an intent's rewards are valid and fully funded
     * @param intent The intent to validate
     * @return True if the intent is properly funded
     */
    function isIntentFunded(
        Intent calldata intent
    ) external view returns (bool);

    /**
     * @notice Checks if an intent's rewards are valid and fully funded
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @return True if the intent is properly funded
     */
    function isIntentFunded(
        uint64 destination,
        bytes memory route,
        Reward calldata reward
    ) external view returns (bool);

    /**
     * @notice Creates a new cross-chain intent with associated rewards
     * @dev Intent must be proven on source chain before expiration for valid reward claims
     * @param intent The complete intent specification
     * @return intentHash Unique identifier of the created intent
     * @return vault Address of the created vault
     */
    function publish(
        Intent calldata intent
    ) external returns (bytes32 intentHash, address vault);

    /**
     * @notice Creates a new cross-chain intent with associated rewards
     * @dev Intent must be proven on source chain before expiration for valid reward claims
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @return intentHash Unique identifier of the created intent
     * @return vault Address of the created vault
     */
    function publish(
        uint64 destination,
        bytes memory route,
        Reward memory reward
    ) external returns (bytes32 intentHash, address vault);

    /**
     * @notice Creates and funds an intent in a single transaction
     * @param intent The complete intent specification
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Unique identifier of the created and funded intent
     * @return vault Address of the created vault
     */
    function publishAndFund(
        Intent calldata intent,
        bool allowPartial
    ) external payable returns (bytes32 intentHash, address vault);

    /**
     * @notice Creates and funds an intent in a single transaction
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @param allowPartial Whether to allow partial funding
     * @return intentHash Unique identifier of the created and funded intent
     * @return vault Address of the created vault
     */
    function publishAndFund(
        uint64 destination,
        bytes memory route,
        Reward memory reward,
        bool allowPartial
    ) external payable returns (bytes32 intentHash, address vault);

    /**
     * @notice Funds an existing intent
     * @param destination Destination chain ID for the intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     * @param allowPartial Whether to allow partial funding
     * @return intentHash The hash of the funded intent
     */
    function fund(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        bool allowPartial
    ) external payable returns (bytes32 intentHash);

    /**
     * @notice Funds an intent on behalf of another address using permit
     * @param destination Destination chain ID for the intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     * @param allowPartial Whether to accept partial funding
     * @param fundingAddress The address providing the funding
     * @param permitContract The permit contract address for external token approvals
     * @return intentHash The hash of the funded intent
     */
    function fundFor(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        bool allowPartial,
        address fundingAddress,
        address permitContract
    ) external payable returns (bytes32 intentHash);

    /**
     * @notice Creates and funds an intent on behalf of another address
     * @param intent The complete intent specification
     * @param allowPartial Whether to accept partial funding
     * @param funder The address providing the funding
     * @param permitContract The permit contract for token approvals
     * @return intentHash The hash of the created and funded intent
     * @return vault Address of the created vault
     */
    function publishAndFundFor(
        Intent calldata intent,
        bool allowPartial,
        address funder,
        address permitContract
    ) external payable returns (bytes32 intentHash, address vault);

    /**
     * @notice Creates and funds an intent on behalf of another address
     * @param destination Destination chain ID for the intent
     * @param route Encoded route data for the intent as bytes
     * @param reward The reward structure containing distribution details
     * @param allowPartial Whether to accept partial funding
     * @param funder The address providing the funding
     * @param permitContract The permit contract for token approvals
     * @return intentHash The hash of the created and funded intent
     * @return vault Address of the created vault
     */
    function publishAndFundFor(
        uint64 destination,
        bytes memory route,
        Reward calldata reward,
        bool allowPartial,
        address funder,
        address permitContract
    ) external payable returns (bytes32 intentHash, address vault);

    /**
     * @notice Claims rewards for a successfully fulfilled and proven intent
     * @param destination Destination chain ID for the intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     */
    function withdraw(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward
    ) external;

    /**
     * @notice Claims rewards for multiple fulfilled and proven intents
     * @param destinations Array of destination chain IDs for the intents
     * @param routeHashes Array of route component hashes
     * @param rewards Array of corresponding reward specifications
     */
    function batchWithdraw(
        uint64[] calldata destinations,
        bytes32[] calldata routeHashes,
        Reward[] calldata rewards
    ) external;

    /**
     * @notice Returns rewards to the intent creator
     * @param destination Destination chain ID for the intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     */
    function refund(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward
    ) external;

    /**
     * @notice Returns rewards to a specified address (only callable by reward creator)
     * @param destination Destination chain ID for the intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     * @param refundee Address to receive the refunded rewards
     */
    function refundTo(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        address refundee
    ) external;

    /**
     * @notice Recovers mistakenly transferred tokens from the intent vault
     * @dev Token must not be part of the intent's reward structure
     * @param destination Destination chain ID for the intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     * @param token The address of the token to recover
     */
    function recoverToken(
        uint64 destination,
        bytes32 routeHash,
        Reward calldata reward,
        address token
    ) external;
}
