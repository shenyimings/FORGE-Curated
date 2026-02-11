// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract PropertiesConstants {
    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);
    uint256 constant INITIAL_BALANCE = 1000e30;
    uint184 constant MAX_UNDERLYING_SUPPLY = type(uint128).max;
    address constant ECHIDNA_TEST_ADDRESS = 0x00a329c0648769A73afAc7F9381E08FB43dBEA72;

    // Protocol constants
    int256 constant BLOCK_TIME = 1;
    uint256 constant MIN_TEST_ASSETS = 1e8;
    uint256 constant MAX_TEST_ASSETS = 1e28;
    uint184 constant CAP = type(uint128).max;
    uint256 constant NB_MARKETS = 3;
    uint256 constant TIMELOCK = 1 weeks;
    uint256 constant MAX_FEE = 0.5e18;
    /// @dev The maximum delay of a timelock.
    uint256 internal constant MAX_TIMELOCK = 2 weeks;

    /// @dev The minimum delay of a timelock.
    uint256 internal constant MIN_TIMELOCK = 1 days;

    // Suite constants
    uint256 constant MAX_NUM_MARKETS = 4;
    uint256 constant WAD = 1e18;

    uint256 constant EULER_EARN_VAULTS_NUM = 2;

    uint256 constant CAP1 = 10_000_000e18; // 10M
    uint256 constant CAP2 = 100_000e18; // 100k
    uint256 constant CAP3 = 1_000_000e18; // 1M
}
