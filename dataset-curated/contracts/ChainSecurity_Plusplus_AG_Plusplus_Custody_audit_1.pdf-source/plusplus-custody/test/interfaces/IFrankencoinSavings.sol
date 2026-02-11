// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IFrankencoinSavings
/// @notice Interface for interacting with the Frankencoin savings module. The
/// ZCHFSavingsManager depends on this interface to deposit and withdraw
/// tokens and query interest parameters.
interface IFrankencoinSavings {
    /// @notice Deposits an amount of tokens into the savings module. The
    /// implementation should pull the tokens from the caller (typically the
    /// savings manager) and credit interest starting from the current
    /// tick after an initial delay.
    /// @param amount The number of tokens to deposit.
    function save(uint192 amount) external;

    /// @notice Returns the current tick value for a given timestamp. In a real
    /// implementation this typically increases over time based on the
    /// interest rate. Our mock allows tests to set arbitrary values.
    /// @param timestamp The timestamp to query the tick for.
    /// @return tick The tick value at the given timestamp.
    function ticks(uint256 timestamp) external view returns (uint64 tick);

    /// @notice Returns the current tick value for a given timestamp. In a real
    /// implementation this typically increases over time based on the
    /// interest rate. Our mock allows tests to set arbitrary values.
    /// @return tick The tick value at the given timestamp.
    function currentTicks() external view returns (uint64 tick);

    /// @notice Returns the current interest rate in parts-per-million per tick.
    /// @return rate The interest rate used to compute the tick delay.
    function currentRatePPM() external view returns (uint24 rate);

    /// @notice Returns the delay before interest starts accruing. Typically
    /// three days in the real contract.
    /// @return delay The delay in seconds.
    function INTEREST_DELAY() external view returns (uint64 delay);

    /// @notice Withdraws an amount of tokens to a target address. The
    /// implementation should calculate and distribute any accrued interest.
    /// @param target The address to receive the withdrawn tokens.
    /// @param amount The number of tokens requested. If more is requested
    ///               than available, the implementation may withdraw fewer.
    /// @return withdrawn The actual number of tokens withdrawn.
    function withdraw(address target, uint192 amount) external returns (uint256 withdrawn);
}
