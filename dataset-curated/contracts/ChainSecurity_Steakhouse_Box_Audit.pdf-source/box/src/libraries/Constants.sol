// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Steakhouse
pragma solidity >=0.8.0;

// Precision for percentage calculations
uint256 constant PRECISION = 1 ether;
// Maximum timelock duration (4 weeks)
uint256 constant TIMELOCK_CAP = 4 weeks;
// Timelock duration for disabled selectors
uint256 constant TIMELOCK_DISABLED = type(uint256).max;
// Maximum allowed slippage percentage (1%)
uint256 constant MAX_SLIPPAGE_LIMIT = 0.01 ether;
// Delay from start of a shutdown to possible liquidations
uint256 constant MAX_SHUTDOWN_WARMUP = 4 weeks;
// Precision for oracle prices
uint256 constant ORACLE_PRECISION = 1e36;
// Maximum number of tokens allowed in a box
uint256 constant MAX_TOKENS = 20;
