// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IZCHFErrors {
    /// @notice Thrown when a deposit with the given identifier already exists
    error DepositAlreadyExists(bytes32 identifier);

    /// @notice Thrown when a deposit with the given identifier is not found
    error DepositNotFound(bytes32 identifier);

    /// @notice Thrown when expected positive amount is given as zero
    error ZeroAmount();

    /// @notice Thrown when transferFrom fails
    error TransferFromFailed(address from, address to, uint256 amount);

    /// @notice Thrown when an address lacks the RECEIVER_ROLE
    error InvalidReceiver(address receiver);

    /// @notice Thrown when input arrays do not match in length or other argument errors occur
    error InvalidArgument();

    /// @notice Thrown when withdrawal from the savings module is not the expected amount
    error UnexpectedWithdrawalAmount();

    /// @notice Thrown when a timestamp is before the last rate change, which would cause an underflow in the savings module
    error TimestampBeforeLastRateChange(uint256 timestamp);
}
