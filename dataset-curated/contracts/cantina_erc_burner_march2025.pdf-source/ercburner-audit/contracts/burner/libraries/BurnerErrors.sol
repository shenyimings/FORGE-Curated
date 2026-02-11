// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Burner Errors
/// @notice Custom errors used in the Burner contract
library BurnerErrors {
    /// @notice Emitted when an invalid command is used
    /// @param command The invalid command
    error InvalidCommand(
        bytes1 command
    );

    /// @notice Emitted when an invalid recipient is used
    /// @param recipient The invalid recipient
    error InvalidRecipient(
        address recipient
    );

    /// @notice Emitted when the commands are invalid
    /// @param commands The invalid commands
    error InvalidCommands(
        bytes commands
    );

    /// @notice Emitted when the inputs are mismatched
    /// @param length The length of the inputs
    error MismatchedInputs(
        uint256 length
    );

    /// @notice Emitted when the input length is mismatched
    /// @param inputs The inputs
    error MismatchedInputLength(
        bytes[] inputs
    );

    /// @notice Emitted when the bridge data must be empty
    /// @param bridgeData The bridge data
    error BridgeDataMustBeEmpty(
        bytes bridgeData
    );

    /// @notice Emitted when the bridge and recipient are both set
    /// @param to The recipient
    error BridgeAndRecipientBothSet(
        address to
    );

    /// @notice Emitted when the recipient must be set
    error RecipientMustBeSet();

    /// @notice Emitted when the bridge data is invalid
    error InvalidBridgeData();

    /// @notice Emitted when the referrer cannot be the self
    error ReferrerCannotBeSelf();

    /// @notice Emitted when the referrer cannot be the fee collector
    error ReferrerCannotBeFeeCollector();

    /// @notice Emitted when the referrer cannot be the contract
    error ReferrerCannotBeContract();

    /// @notice Emitted when a referrer is not registered
    error ReferrerNotRegistered();

    /// @notice Emitted when the to cannot be the contract
    error ToCannotBeContract();

    /// @notice Emitted when the to cannot be the fee collector
    error ToCannotBeFeeCollector();

    /// @notice Emitted when there is an issue with the swap
    /// @param preBalance The pre-balance
    /// @param postBalance The post-balance
    error SwapIssue(
        uint256 preBalance,
        uint256 postBalance
    );

    /// @notice Emitted when there is an issue with the swap
    /// @param sender The sender
    /// @param tokenIn The token in
    /// @param amountIn The amount in
    /// @param reason The reason
    error AvaxSwapIssue(
        address sender,
        address tokenIn,
        uint256 amountIn,
        string reason
    );

    /// @notice Emitted when the total output is insufficient
    /// @param totalOutput The total output
    /// @param minRequired The minimum required
    error InsufficientTotalOutput(
        uint256 totalOutput,
        uint256 minRequired
    );

    /// @notice Emitted when the value is insufficient
    /// @param value The value
    /// @param minRequired The minimum required
    error InsufficientValue(
        uint256 value,
        uint256 minRequired
    );

    /// @notice Emitted when the allowance is insufficient
    /// @param allowance The allowance
    /// @param amount The amount
    error InsufficientAllowanceOrAmount(
        uint256 allowance,
        uint256 amount
    );

    /// @notice Emitted when the value is zero
    error ZeroValue();

    /// @notice Emitted when the fee divisor is too low
    /// @param provided The provided fee divisor
    /// @param minRequired The minimum required
    error FeeDivisorTooLow(
        uint256 provided,
        uint256 minRequired
    );

    /// @notice Emitted when the address is zero
    error ZeroAddress();

    /// @notice Emitted when the min gas for a swap is zero
    error ZeroMinGasForSwap();

    /// @notice Emitted when the max tokens per burn is zero
    error ZeroMaxTokensPerBurn();

    /// @notice Emitted when the bridge is paused
    error BridgePaused();

    /// @notice Emitted when the maximum tier is reached
    error MaximumTierReached();

    /// @notice Emitted when a referrer is already paid
    error ReferrerAlreadyPaid();

    /// @notice Emitted when a referrer is on a partner tier
    error OnPartnerTier();

    /// @notice Emitted when the fee share is too high
    /// @param provided The provided fee share
    /// @param maxAllowed The maximum allowed
    error FeeShareTooHigh(
        uint8 provided,
        uint8 maxAllowed
    );

    /// @notice Emitted when the fee share is zero
    error ZeroFeeShare();

    /// @notice Emitted when the caller is not an admin or owner
    /// @param caller The caller
    error CallerNotAdminOrOwner(
        address caller
    );

    /// @notice Emitted when the admin is the same as the caller
    error SameAdmin();

    /// @notice Emitted when the admin is already set
    error AdminAlreadyExists();

    /// @notice Emitted when the admin does not exist
    error AdminDoesNotExist();
}