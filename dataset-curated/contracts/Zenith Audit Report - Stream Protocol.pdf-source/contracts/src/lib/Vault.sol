// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @title Vault
 * @dev Vault Data Type library for Stream Vaults
 */
library Vault {
    struct VaultParams {
        // Token decimals for vault shares
        uint8 decimals;
        // Minimum supply of the vault shares issued, for ETH it's 10**10
        uint56 minimumSupply;
        // Vault cap
        uint104 cap;
    }

    struct VaultState {
        // 32 byte slot 1
        //  Current round number. `round` represents the number of `period`s elapsed.
        uint16 round;
        // 32 byte slot 2
        // Stores the total tally of how much of `asset` there is
        // to be used to mint share tokens
        uint128 totalPending;
    }

    struct StakeReceipt {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Stake amount, max 20,282,409,603,651 or 20 trillion ETH deposit
        uint104 amount;
        // Unredeemed shares balance
        uint128 unredeemedShares;
    }
}
