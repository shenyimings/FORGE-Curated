// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./IVaultControlStorage.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ERC4626Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IVaultControl
 * @notice Interface for controlling the operational state of a vault, including deposits, withdrawals, limits, and whitelisting.
 * @dev Extends IVaultControlStorage for managing storage and settings related to vault operations.
 */
interface IVaultControl is IVaultControlStorage {
    /**
     * @notice Sets a new limit for the vault to restrict the total value of assets held.
     * @dev Can only be called by an address with the `SET_LIMIT_ROLE`.
     * @param _limit The new limit value to be set.
     */
    function setLimit(uint256 _limit) external;

    /**
     * @notice Pauses withdrawals from the vault.
     * @dev Once paused, no withdrawals can be processed until unpaused.
     * @dev Can only be called by an address with the `PAUSE_WITHDRAWALS_ROLE`.
     * @custom:effects
     * - Emits a `WithdrawalPauseSet` event with `paused` set to `true`.
     * - Revokes the `PAUSE_WITHDRAWALS_ROLE` from `msg.sender`
     */
    function pauseWithdrawals() external;

    /**
     * @notice Unpauses withdrawals from the vault.
     * @dev Once unpaused, withdrawals can be processed again.
     * @dev Can only be called by an address with the `UNPAUSE_WITHDRAWALS_ROLE`.
     * @custom:effects
     * - Emits a `WithdrawalPauseSet` event with `paused` set to `false`.
     */
    function unpauseWithdrawals() external;

    /**
     * @notice Pauses deposits into the vault.
     * @dev Once paused, no deposits can be made until unpaused.
     * @dev Can only be called by an address with the `PAUSE_DEPOSITS_ROLE`.
     * @custom:effects
     * - Emits a `DepositPauseSet` event with `paused` set to `true`.
     * - Revokes the `PAUSE_DEPOSITS_ROLE` from `msg.sender`
     */
    function pauseDeposits() external;

    /**
     * @notice Unpauses deposits into the vault.
     * @dev Once unpaused, deposits can be made again.
     * @dev Can only be called by an address with the `UNPAUSE_DEPOSITS_ROLE`.
     * @custom:effects
     * - Emits a `DepositPauseSet` event with `paused` set to `false`.
     */
    function unpauseDeposits() external;

    /**
     * @notice Sets the deposit whitelist status for the vault.
     * @dev When the whitelist is enabled, only addresses on the whitelist can deposit into the vault.
     * @dev Can only be called by an address with the `SET_DEPOSIT_WHITELIST_ROLE`.
     * @param status The new whitelist status (`true` to enable, `false` to disable).
     * @custom:effects
     * - Emits a `DepositWhitelistSet` event indicating the new whitelist status.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Updates the whitelist status of a specific account.
     * @dev Allows the contract to grant or revoke the ability of an account to make deposits based on the whitelist.
     * @dev Can only be called by an address with the `SET_DEPOSITOR_WHITELIST_STATUS_ROLE`.
     * @param account The address of the account to be updated.
     * @param status The new whitelist status for the account (`true` for whitelisted, `false` for not whitelisted).
     * @custom:effects
     * - Emits a `DepositorWhitelistStatusSet` event indicating the updated whitelist status for the account.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;
}
