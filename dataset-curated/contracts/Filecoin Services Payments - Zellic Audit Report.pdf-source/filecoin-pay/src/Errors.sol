// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

/// @title Errors
/// @notice Centralized library for custom error definitions across the protocol
/// @dev Convention: For any error comparing two values, always pass the expected value first, followed by the actual value
library Errors {
    /// @notice Rail does not exist or is beyond its last settlement after termination
    /// @param railId The ID of the rail
    error RailInactiveOrSettled(uint256 railId);

    /// @notice Only the rail client can perform this action
    /// @param expected The expected client address
    /// @param caller The actual caller address
    error OnlyRailClientAllowed(address expected, address caller);

    /// @notice Only the rail operator can perform this action
    /// @param expected The expected operator address
    /// @param caller The actual caller address
    error OnlyRailOperatorAllowed(address expected, address caller);

    /// @notice Only the rail participant (client, operator, or recipient) can perform this action
    /// @param expectedFrom The expected client address
    /// @param expectedOperator The expected operator address
    /// @param expectedTo The expected recipient address
    /// @param caller The actual caller address
    error OnlyRailParticipantAllowed(address expectedFrom, address expectedOperator, address expectedTo, address caller);

    /// @notice Rail is already terminated
    /// @param railId The ID of the rail
    error RailAlreadyTerminated(uint256 railId);

    /// @notice Rail is not terminated, but the action requires a terminated rail
    /// @param railId The ID of the rail
    error RailNotTerminated(uint256 railId);

    /// @notice The provided address is zero, which is not allowed
    /// @param varName The name of the variable that was expected to be non-zero
    error ZeroAddressNotAllowed(string varName);

    /// @notice One-time payment exceeds the lockup amount for the rail
    /// @param railId The ID of the rail
    /// @param available The available lockup amount for the rail
    /// @param required The required lockup amount for the rail
    error OneTimePaymentExceedsLockup(uint256 railId, uint256 available, uint256 required);

    /// @notice The caller is not authorized to terminate the rail
    /// @dev Only the rail operator or the rail client (with fully settled lockup) can terminate the rail
    /// @param railId The ID of the rail being terminated
    /// @param allowedClient The rail client address (from)
    /// @param allowedOperator The rail operator address
    /// @param caller The address attempting to terminate the rail
    error NotAuthorizedToTerminateRail(uint256 railId, address allowedClient, address allowedOperator, address caller);

    /// @notice The payer's lockup rate is inconsistent with the rail's payment rate
    /// @dev Indicates that the payer's lockup rate is less than the rail's payment rate, which should not occur
    /// @param railId The ID of the rail to terminate
    /// @param from The address of the payer
    /// @param paymentRate The payment rate for the rail
    /// @param lockupRate The current lockup rate of the payer
    error LockupRateInconsistent(uint256 railId, address from, uint256 paymentRate, uint256 lockupRate);

    /// @notice Ether sent must equal the amount for native token transfers
    /// @param required The required amount (must match msg.value)
    /// @param sent The msg.value sent with the transaction
    error MustSendExactNativeAmount(uint256 required, uint256 sent);

    /// @notice Ether (msg.value) must not be sent when transferring ERC20 tokens
    /// @param sent The msg.value sent with the transaction
    error NativeTokenNotAccepted(uint256 sent);

    /// @notice Native tokens are not supported in depositWithPermit; only ERC20 tokens are allowed
    error NativeTokenNotSupported();

    /// @notice Attempted to withdraw more than the available unlocked funds
    /// @param available The amount of unlocked funds available for withdrawal
    /// @param requested The amount requested for withdrawal
    error InsufficientUnlockedFunds(uint256 available, uint256 requested);

    /// @notice The receiving contract rejected the native token transfer
    /// @param to The address to which the transfer was attempted
    /// @param amount The amount of native token attempted to send
    error NativeTransferFailed(address to, uint256 amount);

    /// @notice The operator is not approved for the client (from address)
    /// @param from The address of the client (payer)
    /// @param operator The operator attempting the action
    error OperatorNotApproved(address from, address operator);

    /// @notice The specified commission rate exceeds the allowed maximum.
    /// @param maxAllowed The maximum allowed commission rate in basis points (BPS)
    /// @param actual The actual commission rate that was attempted to be set
    error CommissionRateTooHigh(uint256 maxAllowed, uint256 actual);

    /// @notice A non-zero commission rate was provided, but no service fee recipient was set
    error MissingServiceFeeRecipient();

    /// @notice Invalid attempt to modify a terminated rail's lockup settings
    /// @param actualPeriod The rail's actual period value
    /// @param actualLockupFixed The current lockupFixed value
    /// @param attemptedPeriod The period value provided
    /// @param attemptedLockupFixed The new lockupFixed value proposed
    error InvalidTerminatedRailModification(
        uint256 actualPeriod, uint256 actualLockupFixed, uint256 attemptedPeriod, uint256 attemptedLockupFixed
    );

    /// @notice The payer's current lockup is insufficient to cover the requested lockup reduction
    /// @param from The address of the payer
    /// @param token The token involved in the lockup
    /// @param currentLockup The payer's current lockup amount
    /// @param lockupReduction The reduction attempted to be made
    error InsufficientCurrentLockup(address from, address token, uint256 currentLockup, uint256 lockupReduction);

    /// @notice Cannot change the lockup period due to insufficient funds to cover the current lockup
    /// @param token The token for the lockup
    /// @param from The address whose account is checked (from)
    /// @param actualLockupPeriod The current rail lockup period
    /// @param attemptedLockupPeriod The new period requested
    error LockupPeriodChangeNotAllowedDueToInsufficientFunds(
        address token, address from, uint256 actualLockupPeriod, uint256 attemptedLockupPeriod
    );

    /// @notice Cannot increase the fixed lockup due to insufficient funds to cover the current lockup
    /// @param token The token for the lockup
    /// @param from The address whose account is checked
    /// @param actualLockupFixed The current rail fixed lockup amount
    /// @param attemptedLockupFixed The new fixed lockup amount requested
    error LockupFixedIncreaseNotAllowedDueToInsufficientFunds(
        address token, address from, uint256 actualLockupFixed, uint256 attemptedLockupFixed
    );

    /// @notice The requested lockup period exceeds the operator's maximum allowed lockup period
    /// @param token The token for the lockup
    /// @param operator The operator for the rail
    /// @param maxAllowedPeriod The operator's maximum allowed lockup period
    /// @param requestedPeriod The lockup period requested
    error LockupPeriodExceedsOperatorMaximum(
        address token, address operator, uint256 maxAllowedPeriod, uint256 requestedPeriod
    );

    /// @notice The payer's current lockup is less than the old lockup value
    /// @param token The token for the lockup
    /// @param from The address whose account is checked
    /// @param oldLockup The calculated old lockup amount
    /// @param currentLockup The current lockup value in the account
    error CurrentLockupLessThanOldLockup(address token, address from, uint256 oldLockup, uint256 currentLockup);

    /// @notice Cannot modify a terminated rail beyond its end epoch
    /// @param railId The ID of the rail
    /// @param maxSettlementEpoch The last allowed block for modifications
    /// @param blockNumber The current block number
    error CannotModifyTerminatedRailBeyondEndEpoch(uint256 railId, uint256 maxSettlementEpoch, uint256 blockNumber);

    /// @notice Cannot increase the payment rate or change the rate on a terminated rail
    /// @param railId The ID of the rail
    error RateChangeNotAllowedOnTerminatedRail(uint256 railId);

    /// @notice Account lockup must be fully settled to change the payment rate on an active rail
    /// @param railId The ID of the rail
    /// @param from The address whose lockup is being checked
    /// @param isSettled Whether the account lockup is fully settled
    /// @param currentRate The current payment rate
    /// @param attemptedRate The attempted new payment rate
    error LockupNotSettledRateChangeNotAllowed(
        uint256 railId, address from, bool isSettled, uint256 currentRate, uint256 attemptedRate
    );

    /// @notice Payer's lockup rate is less than the old payment rate when updating an active rail
    /// @param railId The ID of the rail
    /// @param from The address whose lockup is being checked
    /// @param lockupRate The current lockup rate of the payer
    /// @param oldRate The current payment rate for the rail
    error LockupRateLessThanOldRate(uint256 railId, address from, uint256 lockupRate, uint256 oldRate);

    /// @notice The payer does not have enough funds for the one-time payment
    /// @param token The token being used for payment
    /// @param from The payer's address
    /// @param required The amount required (oneTimePayment)
    /// @param actual The actual funds available in the payer's account
    error InsufficientFundsForOneTimePayment(address token, address from, uint256 required, uint256 actual);

    /// @notice Cannot settle a terminated rail without validation until after the max settlement epoch has passed
    /// @param railId The ID of the rail being settled
    /// @param currentBlock The current block number (actual)
    /// @param requiredBlock The max settlement epoch block (expected, must be exceeded)
    error CannotSettleTerminatedRailBeforeMaxEpoch(
        uint256 railId,
        uint256 requiredBlock, // expected (maxSettleEpoch + 1)
        uint256 currentBlock // actual (block.number)
    );

    /// @notice Cannot settle a rail for epochs in the future.
    /// @param railId The ID of the rail being settled
    /// @param maxAllowedEpoch The latest epoch that can be settled (expected, must be >= actual)
    /// @param attemptedEpoch The epoch up to which settlement was attempted (actual)
    error CannotSettleFutureEpochs(uint256 railId, uint256 maxAllowedEpoch, uint256 attemptedEpoch);

    /// @notice No progress was made in settlement; settledUpTo did not advance.
    /// @param railId The ID of the rail
    /// @param expectedSettledUpTo The expected value for settledUpTo (must be > startEpoch)
    /// @param actualSettledUpTo The actual value after settlement attempt
    error NoProgressInSettlement(uint256 railId, uint256 expectedSettledUpTo, uint256 actualSettledUpTo);

    /// @notice The payer's current lockup is less than the fixed lockup amount during rail finalization.
    /// @param railId The ID of the rail being finalized
    /// @param token The token used for the rail
    /// @param from The address whose lockup is being reduced
    /// @param expectedLockup The expected minimum lockup amount (rail.lockupFixed)
    /// @param actualLockup The actual current lockup in the payer's account (payer.lockupCurrent)
    error LockupInconsistencyDuringRailFinalization(
        uint256 railId, address token, address from, uint256 expectedLockup, uint256 actualLockup
    );

    /// @notice The next rate change in the queue is scheduled before the current processed epoch, indicating an invalid state.
    /// @param nextRateChangeUntilEpoch The untilEpoch of the next rate change in the queue
    /// @param processedEpoch The epoch that has been processed up to
    error InvalidRateChangeQueueState(uint256 nextRateChangeUntilEpoch, uint256 processedEpoch);

    /// @notice The validator attempted to settle an epoch before the allowed segment start
    /// @param railId The ID of the rail being settled
    /// @param allowedStart The minimum epoch allowed (segment start)
    /// @param attemptedStart The epoch at which settlement was attempted
    error ValidatorSettledBeforeSegmentStart(uint256 railId, uint256 allowedStart, uint256 attemptedStart);

    /// @notice The validator attempted to settle an epoch beyond the allowed segment end
    /// @param railId The ID of the rail being settled
    /// @param allowedEnd The maximum epoch allowed (segment end)
    /// @param attemptedEnd The epoch at which settlement was attempted
    error ValidatorSettledBeyondSegmentEnd(uint256 railId, uint256 allowedEnd, uint256 attemptedEnd);

    /// @notice The validator returned a modified amount exceeding the maximum allowed for the confirmed epochs
    /// @param railId The ID of the rail being settled
    /// @param maxAllowed The maximum allowed settlement amount for the segment
    /// @param attempted The attempted (modified) settlement amount
    error ValidatorModifiedAmountExceedsMaximum(uint256 railId, uint256 maxAllowed, uint256 attempted);

    /// @notice The account does not have enough funds to cover the required settlement amount
    /// @param token The token used for the settlement
    /// @param from The address of the account being checked
    /// @param available The actual funds available in the account
    /// @param required The amount required for settlement
    error InsufficientFundsForSettlement(address token, address from, uint256 available, uint256 required);

    /// @notice The payer does not have enough lockup to cover the required settlement amount
    /// @param token The token used for the settlement
    /// @param from The payer address being checked
    /// @param available The actual lockup available in the account
    /// @param required The required lockup amount for the settlement
    error InsufficientLockupForSettlement(address token, address from, uint256 available, uint256 required);

    /// @notice Invariant violation: The payer's lockup exceeds their available funds after settlement
    /// @dev Indicates a critical accounting bug or logic error in the settlement process.
    /// @param token The token being checked
    /// @param account The address whose lockup is being checked
    /// @param lockupCurrent The current lockup amount
    /// @param fundsCurrent The current funds available
    error LockupExceedsFundsInvariant(address token, address account, uint256 lockupCurrent, uint256 fundsCurrent);

    /// @notice The rate change queue must be empty after full settlement, but it's not
    /// @param nextUntilEpoch The untilEpoch value of the next queued rate change (tail of the queue)
    error RateChangeQueueNotEmpty(uint256 nextUntilEpoch);

    /// @notice The attempted operation exceeds the operator's allowed rate usage
    /// @param allowed The total rate allowance for the operator
    /// @param attemptedUsage The rate usage attempted after increase
    error OperatorRateAllowanceExceeded(uint256 allowed, uint256 attemptedUsage);

    /// @notice The attempted operation exceeds the operator's allowed lockup usage
    /// @param allowed The total lockup allowance for the operator
    /// @param attemptedUsage The lockup usage attempted after increase
    error OperatorLockupAllowanceExceeded(uint256 allowed, uint256 attemptedUsage);

    /// @notice Attempted to withdraw more than the accumulated fees for the given token
    /// @param token The token address
    /// @param available The current accumulated fees
    /// @param requested The amount attempted to withdraw
    error WithdrawAmountExceedsAccumulatedFees(address token, uint256 available, uint256 requested);

    /// @notice Native token transfer failed during fee withdrawal
    /// @param to The recipient address
    /// @param amount The amount attempted to send
    error FeeWithdrawalNativeTransferFailed(address to, uint256 amount);

    /// @notice Not enough native token sent for the burn operation
    /// @param required The minimum required native token amount
    /// @param sent The amount of native token sent with the transaction
    error InsufficientNativeTokenForBurn(uint256 required, uint256 sent);

    /// @notice The 'to' address in permit functions must be the message sender
    /// @param expected The expected address (msg.sender)
    /// @param actual The actual 'to' address provided
    error PermitRecipientMustBeMsgSender(address expected, address actual);
}
