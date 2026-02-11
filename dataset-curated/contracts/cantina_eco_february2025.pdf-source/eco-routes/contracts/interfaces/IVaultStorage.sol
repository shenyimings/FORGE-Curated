/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IVaultStorage
 * @notice Interface for the storage layout of the Vault contract
 */
interface IVaultStorage {
    enum RewardStatus {
        Initial,
        PartiallyFunded,
        Funded,
        Claimed,
        Refunded
    }

    /**
     * @notice Mode of the vault contract
     */
    enum VaultMode {
        Fund,
        Claim,
        Refund,
        RecoverToken
    }

    /**
     * @notice Status of the vault contract
     * @dev Tracks the current mode and funding status
     * @param status Current status of the vault
     * @param mode Current mode of the vault
     * @param allowPartial Whether partial funding is allowed
     * @param usePermit Whether permit is enabled
     * @param target Address of the funder in Fund, claimant in Claim or refund token in RecoverToken mode
     */
    struct VaultState {
        uint8 status; // RewardStatus
        uint8 mode; // VaultMode
        uint8 allowPartialFunding; // boolean
        uint8 usePermit; // boolean
        address target; // funder, claimant or refund token address
    }

    /**
     * @notice Storage for the vault contract
     * @dev Tracks the current state and permit contract instance
     * @param state Current state of the vault
     * @param permitContract Address of the permit contract instance
     */
    struct VaultStorage {
        VaultState state; // 1 bytes32 storage slot
        address permitContract; // permit instance when enabled
    }
}
