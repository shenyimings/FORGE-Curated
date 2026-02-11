// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

uint8 constant NAV_DECIMALS = 8;

// Define the Shares contract INVESTOR role ID
bytes32 constant INVESTOR = keccak256("INVESTOR"); // 0x5614e11ca6d7673c9c8dcec913465d676494aad1151bb2c1cf40b9d99be4d935

// Define the NAVCalculator contract MANAGER role ID
bytes32 constant MANAGER = keccak256("MANAGER"); // 0xaf290d8680820aad922855f39b306097b20e28774d6c1ad35a20325630c3a02c

// Define the OPERATOR role ID, used for the Shares contract and for the bridging operations in the NAVCalculator
// contract
bytes32 constant OPERATOR = keccak256("OPERATOR"); // 0x523a704056dcd17bcf83bed8b68c59416dac1119be77755efe3bde0a64e46e0c

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

uint256 constant ONE_HUNDRED_PERCENT = 100e18;

uint256 constant TEN_PERCENT = 10e18;

// Number of seconds in a year (365 days)
uint256 constant SECONDS_PER_YEAR = 365 days;

uint256 constant MIN_TIME_ELAPSED = 1 days;
