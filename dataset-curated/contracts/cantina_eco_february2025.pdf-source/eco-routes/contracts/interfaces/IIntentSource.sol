/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemver} from "./ISemver.sol";
import {IVaultStorage} from "./IVaultStorage.sol";

import {Intent, Reward, Call, TokenAmount} from "../types/Intent.sol";

/**
 * @title IIntentSource
 * @notice Interface for managing cross-chain intents and their associated rewards on the source chain
 * @dev This contract works in conjunction with an inbox contract on the destination chain
 *      and a prover contract for verification. It handles intent creation, funding,
 *      and reward distribution.
 */
interface IIntentSource is ISemver, IVaultStorage {
    /**
     * @notice Indicates an attempt to fund an intent on an incorrect chain
     * @param intentHash The hash of the intent that was incorrectly targeted
     */
    error WrongSourceChain(bytes32 intentHash);

    /**
     * @notice Indicates a failed native token transfer during reward distribution
     * @param intentHash The hash of the intent whose reward transfer failed
     */
    error NativeRewardTransferFailed(bytes32 intentHash);

    /**
     * @notice Indicates an attempt to publish a duplicate intent
     * @param intentHash The hash of the pre-existing intent
     */
    error IntentAlreadyExists(bytes32 intentHash);

    /**
     * @notice Indicates an attempt to fund an already funded intent
     * @param intentHash The hash of the previously funded intent
     */
    error IntentAlreadyFunded(bytes32 intentHash);

    /**
     * @notice Indicates insufficient native token payment for the required reward
     * @param intentHash The hash of the intent with insufficient funding
     */
    error InsufficientNativeReward(bytes32 intentHash);

    /**
     * @notice Indicates an invalid attempt to fund with native tokens
     * @param intentHash The hash of the intent that cannot accept native tokens
     */
    error CannotFundForWithNativeReward(bytes32 intentHash);

    /**
     * @notice Indicates an unauthorized reward withdrawal attempt
     * @param _hash The hash of the intent with protected rewards
     */
    error UnauthorizedWithdrawal(bytes32 _hash);

    /**
     * @notice Indicates an attempt to withdraw already claimed rewards
     * @param _hash The hash of the intent with depleted rewards
     */
    error RewardsAlreadyWithdrawn(bytes32 _hash);

    /**
     * @notice Indicates a premature withdrawal attempt before intent expiration
     * @param intentHash The hash of the unexpired intent
     */
    error IntentNotExpired(bytes32 intentHash);

    /**
     * @notice Indicates a premature refund attempt before intent completion
     * @param intentHash The hash of the unclaimed intent
     */
    error IntentNotClaimed(bytes32 intentHash);

    /**
     * @notice Indicates an invalid token specified for refund
     */
    error InvalidRefundToken();

    /**
     * @notice Indicates mismatched array lengths in batch operations
     */
    error ArrayLengthMismatch();

    /**
     * @notice Signals partial funding of an intent with native tokens
     * @param intentHash The hash of the partially funded intent
     * @param fundingSource The address providing the partial funding
     */
    event IntentPartiallyFunded(bytes32 intentHash, address fundingSource);

    /**
     * @notice Signals complete funding of an intent with native tokens
     * @param intentHash The hash of the fully funded intent
     * @param fundingSource The address providing the complete funding
     */
    event IntentFunded(bytes32 intentHash, address fundingSource);

    /**
     * @notice Signals the creation of a new cross-chain intent
     * @param hash Unique identifier of the intent
     * @param salt Creator-provided uniqueness factor
     * @param source Origin chain identifier
     * @param destination Target chain identifier
     * @param inbox Address of the receiving contract on the destination chain
     * @param routeTokens Required tokens for executing destination chain calls
     * @param calls Instructions to execute on the destination chain
     * @param creator Intent originator address
     * @param prover Verification contract address
     * @param deadline Timestamp for reward claim eligibility
     * @param nativeValue Native token reward amount
     * @param rewardTokens ERC20 token rewards with amounts
     */
    event IntentCreated(
        bytes32 indexed hash,
        bytes32 salt,
        uint256 source,
        uint256 destination,
        address inbox,
        TokenAmount[] routeTokens,
        Call[] calls,
        address indexed creator,
        address indexed prover,
        uint256 deadline,
        uint256 nativeValue,
        TokenAmount[] rewardTokens
    );

    /**
     * @notice Signals successful reward withdrawal
     * @param _hash The hash of the claimed intent
     * @param _recipient The address receiving the rewards
     */
    event Withdrawal(bytes32 _hash, address indexed _recipient);

    /**
     * @notice Signals successful reward refund
     * @param _hash The hash of the refunded intent
     * @param _recipient The address receiving the refund
     */
    event Refund(bytes32 _hash, address indexed _recipient);

    /**
     * @notice Retrieves the current reward claim status for an intent
     * @param intentHash The hash of the queried intent
     * @return status Current reward status
     */
    function getRewardStatus(
        bytes32 intentHash
    ) external view returns (RewardStatus status);

    /**
     * @notice Retrieves the current state of an intent's vault
     * @param intentHash The hash of the intent
     * @return Current vault state
     */
    function getVaultState(
        bytes32 intentHash
    ) external view returns (VaultState memory);

    /**
     * @notice Retrieves the permit contract for token transfers
     * @param intentHash The hash of the intent
     * @return Address of the permit contract
     */
    function getPermitContract(
        bytes32 intentHash
    ) external view returns (address);

    /**
     * @notice Computes the hash components of an intent
     * @param intent The intent to hash
     * @return intentHash Combined hash of route and reward components
     * @return routeHash Hash of the route specifications
     * @return rewardHash Hash of the reward specifications
     */
    function getIntentHash(
        Intent calldata intent
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
     * @notice Creates a new cross-chain intent with associated rewards
     * @dev Intent must be proven on source chain before expiration for valid reward claims
     * @param intent The complete intent specification
     * @return intentHash Unique identifier of the created intent
     */
    function publish(
        Intent calldata intent
    ) external returns (bytes32 intentHash);

    /**
     * @notice Creates and funds an intent in a single transaction
     * @param intent The complete intent specification
     * @return intentHash Unique identifier of the created and funded intent
     */
    function publishAndFund(
        Intent calldata intent
    ) external payable returns (bytes32 intentHash);

    /**
     * @notice Funds an existing intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     * @return intentHash The hash of the funded intent
     */
    function fund(
        bytes32 routeHash,
        Reward calldata reward
    ) external payable returns (bytes32 intentHash);

    /**
     * @notice Funds an intent on behalf of another address using permit
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     * @param fundingAddress The address providing the funding
     * @param permitContract The permit contract address for external token approvals
     * @param allowPartial Whether to accept partial funding
     * @return intentHash The hash of the funded intent
     */
    function fundFor(
        bytes32 routeHash,
        Reward calldata reward,
        address fundingAddress,
        address permitContract,
        bool allowPartial
    ) external returns (bytes32 intentHash);

    /**
     * @notice Creates and funds an intent on behalf of another address
     * @param intent The complete intent specification
     * @param funder The address providing the funding
     * @param permitContact The permit contract for token approvals
     * @param allowPartial Whether to accept partial funding
     * @return intentHash The hash of the created and funded intent
     */
    function publishAndFundFor(
        Intent calldata intent,
        address funder,
        address permitContact,
        bool allowPartial
    ) external returns (bytes32 intentHash);

    /**
     * @notice Checks if an intent's rewards are valid and fully funded
     * @param intent The intent to validate
     * @return True if the intent is properly funded
     */
    function isIntentFunded(
        Intent calldata intent
    ) external view returns (bool);

    /**
     * @notice Claims rewards for a successfully fulfilled intent
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     */
    function withdrawRewards(
        bytes32 routeHash,
        Reward calldata reward
    ) external;

    /**
     * @notice Claims rewards for multiple fulfilled intents
     * @param routeHashes Array of route component hashes
     * @param rewards Array of corresponding reward specifications
     */
    function batchWithdraw(
        bytes32[] calldata routeHashes,
        Reward[] calldata rewards
    ) external;

    /**
     * @notice Returns rewards to the intent creator
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     */
    function refund(bytes32 routeHash, Reward calldata reward) external;

    /**
     * @notice Recovers mistakenly transferred tokens from the intent vault
     * @dev Token must not be part of the intent's reward structure
     * @param routeHash The hash of the intent's route component
     * @param reward The reward specification
     * @param token The address of the token to recover
     */
    function recoverToken(
        bytes32 routeHash,
        Reward calldata reward,
        address token
    ) external;
}
