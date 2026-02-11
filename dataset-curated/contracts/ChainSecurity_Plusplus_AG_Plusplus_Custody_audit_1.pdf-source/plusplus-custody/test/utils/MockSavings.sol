// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFrankencoinSavings} from "../interfaces/IFrankencoinSavings.sol";

/// @title MockSavings
/// @notice A simple mock of the IFrankencoinSavings interface. It allows
/// tests to control the tick counter, interest rate and delay directly. The
/// save and withdraw functions merely update internal accounting without
/// interacting with any real token.
contract MockSavings is IFrankencoinSavings {
    // The current tick value returned by ticks(). Can be set in tests via
    // setTick(). It does not depend on the timestamp to allow arbitrary
    // simulation of interest accrual.
    uint64 public tick;

    // The interest rate in parts-per-million returned by currentRatePPM().
    uint24 public override currentRatePPM;

    // The interest delay returned by INTEREST_DELAY(). This defaults to
    // three days (259200 seconds) but can be changed for specific tests.
    uint64 public override INTEREST_DELAY;

    // Tracks the total amount of tokens saved in the mock module. It is
    // incremented by save() and decremented by withdraw(). This value is
    // exposed for assertions in tests.
    uint192 public saved;

    // Records the last call to withdraw() for inspection. These variables are
    // updated on each call and allow tests to verify the recipient and
    // amount used in the withdrawal.
    address public lastWithdrawTarget;
    uint192 public lastWithdrawAmount;

    /// @notice Constructs the mock with default values for the rate and delay.
    constructor() {
        currentRatePPM = 100; // 0.01% per tick by default
        INTEREST_DELAY = 3 days;
    }

    /// @notice Sets the tick value returned by ticks().
    /// @param _tick The new tick value.
    function setTick(uint64 _tick) external {
        tick = _tick;
    }

    /// @notice Sets the current rate returned by currentRatePPM().
    /// @param rate The new interest rate in parts-per-million per tick.
    function setCurrentRatePPM(uint24 rate) external {
        currentRatePPM = rate;
    }

    /// @notice Sets the interest delay returned by INTEREST_DELAY().
    /// @param delay_ The new delay in seconds.
    function setDelay(uint64 delay_) external {
        INTEREST_DELAY = delay_;
    }

    /// @inheritdoc IFrankencoinSavings
    function ticks(uint256 /*timestamp*/ ) external view override returns (uint64) {
        return tick;
    }

    /// @inheritdoc IFrankencoinSavings
    function currentTicks() external view override returns (uint64) {
        return tick;
    }

    /// @inheritdoc IFrankencoinSavings
    function save(uint192 amount) external override {
        saved += amount;
    }

    /// @inheritdoc IFrankencoinSavings
    function withdraw(address target, uint192 amount) external override returns (uint256) {
        // Ensure we never underflow. If more is requested than available,
        // withdraw the remaining saved amount.
        uint192 withdrawal = amount > saved ? saved : amount;
        saved -= withdrawal;
        lastWithdrawTarget = target;
        lastWithdrawAmount = withdrawal;
        return withdrawal;
    }
}
