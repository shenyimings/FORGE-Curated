// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BaseController } from "./BaseController.sol";
import { VaultManager } from "./VaultManager.sol";

/**
 * @title VaultLimitsLogic
 * @notice Provides logic for calculating vault deposit and withdrawal limits based on capacity and proportionality
 * constraints
 * @dev Abstract contract that implements vault limit calculations considering:
 *      - Maximum vault capacity limits
 *      - Maximum proportionality limits (upper bound on vault's share of total assets)
 *      - Minimum proportionality limits (lower bound on vault's share of total assets)
 *      All calculations are performed using basis points (10,000 = 100%)
 */
abstract contract VaultLimitsLogic is BaseController, VaultManager {
    using Math for uint256;
    using SafeCast for *;

    /**
     * @notice Calculates the maximum deposit limit for a specific vault
     * @dev Determines the maximum amount that can be deposited to a vault considering:
     *      - The vault's maximum capacity limit
     *      - The vault's maximum proportionality constraint
     *      - Other vaults' minimum proportionality constraints
     *      Returns the minimum of all applicable limits
     * @param overview The vaults overview containing current state snapshot
     * @param vault The address of the vault to calculate deposit limit for
     * @return max The maximum amount that can be deposited to the vault
     */
    function _maxDepositLimit(VaultsOverview memory overview, address vault) internal pure returns (uint256 max) {
        max = type(uint256).max;
        bool found;
        for (uint256 i; i < overview.vaults.length; ++i) {
            if (overview.vaults[i] == vault) {
                found = true;
                // this vault: max capacity check
                max = max.min(_maxDepositByThisVaultMaxCapacity(overview, i));
                // this vault: max proportionality checks
                max = max.min(_maxDepositByThisVaultMaxProportionality(overview, i));
            } else {
                // other vault: min proportionality check
                max = max.min(_maxDepositByOtherVaultMinProportionality(overview, i));
            }
        }
        assert(found);
    }

    /**
     * @notice Calculates the maximum withdrawal limit for a specific vault
     * @dev Determines the maximum amount that can be withdrawn from a vault considering:
     *      - The vault's minimum proportionality constraint
     *      - Other vaults' maximum proportionality constraints
     *      Returns the minimum of all applicable limits
     * @param overview The vaults overview containing current state snapshot
     * @param vault The address of the vault to calculate withdrawal limit for
     * @return max The maximum amount that can be withdrawn from the vault
     */
    function _maxWithdrawLimit(VaultsOverview memory overview, address vault) internal pure returns (uint256 max) {
        max = type(uint256).max;
        bool found;
        for (uint256 i; i < overview.vaults.length; ++i) {
            if (overview.vaults[i] == vault) {
                found = true;
                // this vault: min proportionality check
                max = max.min(_maxWithdrawByThisVaultMinProportionality(overview, i));
            } else {
                // other vault: max proportionality check
                max = max.min(_maxWithdrawByOtherVaultMaxProportionality(overview, i));
            }
        }
        assert(found);
    }

    // ========================================
    // HELPERS
    // ========================================

    /**
     * @notice Calculates maximum deposit based on vault's capacity limit
     * @dev Returns the remaining capacity before hitting the vault's maximum capacity limit
     * @param overview The vaults overview containing current state snapshot
     * @param vaultIndex The index of the vault in the overview arrays
     * @return The maximum deposit amount based on capacity constraint, or type(uint256).max if no limit
     */
    function _maxDepositByThisVaultMaxCapacity(
        VaultsOverview memory overview,
        uint256 vaultIndex
    )
        internal
        pure
        returns (uint256)
    {
        uint224 maxCapacity = overview.settings[vaultIndex].maxCapacity;
        uint256 vaultAssets = overview.assets[vaultIndex];

        if (maxCapacity == 0) return type(uint256).max;
        return maxCapacity <= vaultAssets ? 0 : maxCapacity - vaultAssets;
    }

    /**
     * @notice Calculates maximum deposit based on vault's maximum proportionality limit
     * @dev Determines how much can be deposited before the vault exceeds its maximum
     * proportionality relative to total protocol assets
     * @param overview The vaults overview containing current state snapshot
     * @param vaultIndex The index of the vault in the overview arrays
     * @return The maximum deposit amount based on proportionality constraint
     */
    function _maxDepositByThisVaultMaxProportionality(
        VaultsOverview memory overview,
        uint256 vaultIndex
    )
        internal
        pure
        returns (uint256)
    {
        uint16 maxProportionality = overview.settings[vaultIndex].maxProportionality;
        uint256 vaultAssets = overview.assets[vaultIndex];
        uint256 totalAssets = overview.totalAssets;

        // Note: order of these checks is important
        if (maxProportionality == MAX_BPS) return type(uint256).max;
        if (maxProportionality == 0) return 0;
        if (totalAssets == 0) return 0;
        if (vaultAssets == totalAssets) return 0;
        int256 change = _vaultAssetsDeltaToHitProportionality(maxProportionality, vaultAssets, totalAssets);
        // casting to 'uint256' is safe because 'change' sign is checked
        // forge-lint: disable-next-line(unsafe-typecast)
        return change > 0 ? uint256(change) : 0;
    }

    /**
     * @notice Calculates maximum deposit based on other vault's minimum proportionality requirement
     * @dev Determines how much can be deposited to other vaults before target vault
     * falls below its minimum proportionality requirement
     * @param overview The vaults overview containing current state snapshot
     * @param vaultIndex The index of the target vault in the overview arrays
     * @return The maximum deposit amount constrained by other vault's minimum proportionality
     */
    function _maxDepositByOtherVaultMinProportionality(
        VaultsOverview memory overview,
        uint256 vaultIndex
    )
        internal
        pure
        returns (uint256)
    {
        uint16 minProportionality = overview.settings[vaultIndex].minProportionality;
        uint256 vaultAssets = overview.assets[vaultIndex];
        uint256 totalAssets = overview.totalAssets;

        // Note: order of these checks is important
        if (minProportionality == 0) return type(uint256).max;
        if (minProportionality == MAX_BPS) return 0;
        if (vaultAssets == 0) return 0;
        int256 change = _totalAssetsDeltaToHitProportionality(minProportionality, vaultAssets, totalAssets);
        // casting to 'uint256' is safe because 'change' sign is checked
        // forge-lint: disable-next-line(unsafe-typecast)
        return change > 0 ? uint256(change) : 0;
    }

    /**
     * @notice Calculates maximum withdrawal based on vault's minimum proportionality requirement
     * @dev Determines how much can be withdrawn from the vault while maintaining its
     * minimum proportionality relative to total protocol assets
     * @param overview The vaults overview containing current state snapshot
     * @param vaultIndex The index of the vault in the overview arrays
     * @return The maximum withdrawal amount based on minimum proportionality constraint
     */
    function _maxWithdrawByThisVaultMinProportionality(
        VaultsOverview memory overview,
        uint256 vaultIndex
    )
        internal
        pure
        returns (uint256)
    {
        uint16 minProportionality = overview.settings[vaultIndex].minProportionality;
        uint256 vaultAssets = overview.assets[vaultIndex];
        uint256 totalAssets = overview.totalAssets;

        // Note: order of these checks is important
        if (vaultAssets == 0) return 0;
        if (minProportionality == 0) return vaultAssets;
        if (minProportionality == MAX_BPS) return vaultAssets == totalAssets ? vaultAssets : 0;
        if (vaultAssets == totalAssets) return vaultAssets;
        int256 change = _vaultAssetsDeltaToHitProportionality(minProportionality, vaultAssets, totalAssets);
        // casting to 'uint256' is safe because 'change' sign is checked
        // forge-lint: disable-next-line(unsafe-typecast)
        return change < 0 ? uint256(-change) : 0;
    }

    /**
     * @notice Calculates maximum withdrawal based on other vault's maximum proportionality limit
     * @dev Determines how much can be withdrawn from other vaults before target vault
     * exceeds its maximum proportionality relative to total protocol assets
     * @param overview The vaults overview containing current state snapshot
     * @param vaultIndex The index of the target vault in the overview arrays
     * @return The maximum withdrawal amount constrained by other vault's maximum proportionality
     */
    function _maxWithdrawByOtherVaultMaxProportionality(
        VaultsOverview memory overview,
        uint256 vaultIndex
    )
        internal
        pure
        returns (uint256)
    {
        uint16 maxProportionality = overview.settings[vaultIndex].maxProportionality;
        uint256 vaultAssets = overview.assets[vaultIndex];
        uint256 totalAssets = overview.totalAssets;

        // Note: order of these checks is important
        if (vaultAssets == 0) return totalAssets;
        if (maxProportionality == MAX_BPS) return totalAssets - vaultAssets;
        if (maxProportionality == 0) return 0;
        int256 change = _totalAssetsDeltaToHitProportionality(maxProportionality, vaultAssets, totalAssets);
        // casting to 'uint256' is safe because 'change' sign is checked
        // forge-lint: disable-next-line(unsafe-typecast)
        return change < 0 ? uint256(-change) : 0;
    }

    /**
     * @notice Calculates the asset change needed for a vault to reach a target proportionality
     * @dev Computes the signed change in assets needed for the vault to achieve the specified
     * proportionality limit. Positive values indicate assets to add, negative values indicate assets to remove
     * @param proportionalityLimit The target proportionality in basis points (0 < limit < MAX_BPS)
     * @param vaultAssets Current normalized assets in the vault
     * @param totalAssets Total normalized assets across all vaults
     * @return The signed change in assets needed (positive = deposit, negative = withdrawal)
     */
    function _vaultAssetsDeltaToHitProportionality(
        uint16 proportionalityLimit,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        internal
        pure
        returns (int256)
    {
        assert(0 < proportionalityLimit && proportionalityLimit < MAX_BPS);
        assert(totalAssets > 0 && vaultAssets < totalAssets);
        return totalAssets.mulDiv(proportionalityLimit, MAX_BPS - proportionalityLimit).toInt256()
            - vaultAssets.mulDiv(MAX_BPS, MAX_BPS - proportionalityLimit).toInt256();
    }

    /**
     * @notice Calculates the total asset change needed for the target vault to reach a target proportionality
     * @dev Computes the signed change in total protocol assets needed for the specified vault
     * to achieve the target proportionality
     * @param proportionalityLimit The target proportionality in basis points (0 < limit < MAX_BPS)
     * @param vaultAssets Current normalized assets in the target vault
     * @param totalAssets Total normalized assets across all vaults
     * @return The signed change in total assets needed (positive = increase total, negative = decrease total)
     */
    function _totalAssetsDeltaToHitProportionality(
        uint16 proportionalityLimit,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        internal
        pure
        returns (int256)
    {
        assert(0 < proportionalityLimit && proportionalityLimit < MAX_BPS);
        assert(vaultAssets > 0 && vaultAssets <= totalAssets);
        return vaultAssets.mulDiv(MAX_BPS, proportionalityLimit).toInt256() - totalAssets.toInt256();
    }
}
