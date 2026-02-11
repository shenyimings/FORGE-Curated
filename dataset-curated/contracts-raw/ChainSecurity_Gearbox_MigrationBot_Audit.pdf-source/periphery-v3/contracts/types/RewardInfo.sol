// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

struct RewardInfo {
    uint256 amount;
    address rewardToken;
    address stakedPhantomToken;
    address adapter;
}
