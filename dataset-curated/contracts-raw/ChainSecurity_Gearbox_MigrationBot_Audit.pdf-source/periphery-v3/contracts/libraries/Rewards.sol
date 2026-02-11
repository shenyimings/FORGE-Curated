// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {RewardInfo} from "../types/RewardInfo.sol";

/// @title Reward info array operations library
library RewardInfoLib {
    /// @notice Appends a single RewardInfo to an array
    /// @param rewards Original array of RewardInfo
    /// @param reward Single RewardInfo to append
    /// @return newRewards New array with appended RewardInfo
    function append(RewardInfo[] memory rewards, RewardInfo memory reward)
        internal
        pure
        returns (RewardInfo[] memory newRewards)
    {
        newRewards = new RewardInfo[](rewards.length + 1);
        for (uint256 i = 0; i < rewards.length; ++i) {
            newRewards[i] = rewards[i];
        }
        newRewards[rewards.length] = reward;
    }

    /// @notice Concatenates two RewardInfo arrays
    /// @param rewards1 First array of RewardInfo
    /// @param rewards2 Second array of RewardInfo
    /// @return newRewards New concatenated array
    function concat(RewardInfo[] memory rewards1, RewardInfo[] memory rewards2)
        internal
        pure
        returns (RewardInfo[] memory newRewards)
    {
        newRewards = new RewardInfo[](rewards1.length + rewards2.length);
        for (uint256 i = 0; i < rewards1.length; ++i) {
            newRewards[i] = rewards1[i];
        }
        for (uint256 i = 0; i < rewards2.length; ++i) {
            newRewards[rewards1.length + i] = rewards2[i];
        }
    }
}
