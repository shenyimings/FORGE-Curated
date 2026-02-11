// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IWithdrawalQueue
 * @notice Interface to handle the withdrawal process from the underlying vault.
 * @dev Provides functions to manage withdrawals, claimable assets, and interactions with vault epochs.
 */
interface IWithdrawalQueue {
    /**
     * @notice Returns the pending collateral amount for a specific account.
     * @param account The address of the account.
     * @return pendingAssets The total amount of pending collateral for the account.
     */
    function pendingAssetsOf(address account) external view returns (uint256);

    /**
     * @notice Returns the claimable collateral amount for a specific account.
     * @param account The address of the account.
     * @return claimableAssets The total amount of claimable collateral for the account.
     */
    function claimableAssetsOf(address account) external view returns (uint256);

    /**
     * @notice Claims collateral from the External Vault for a specified epoch.
     * @param epoch The epoch number from which to claim collateral.
     *
     * @custom:requirements
     * - The epoch MUST be claimable.
     * - There MUST be claimable withdrawals for the given epoch.
     *
     * @custom:effects
     * - Emits an `EpochClaimed` event.
     */
    function pull(uint256 epoch) external;

    /**
     * @notice Finalizes the collateral claim process for a specific account and transfers it to the recipient.
     * @dev Transfers the lesser of the claimable amount or the specified maximum amount to the recipient.
     * @param account The address of the account to claim collateral from.
     * @param recipient The address of the recipient receiving the collateral.
     * @param maxAmount The maximum amount of collateral to be claimed.
     * @return amount The actual amount of collateral claimed and transferred.
     *
     * @custom:requirements
     * - `msg.sender` MUST be the vault or the account itself.
     * - The claimable amount MUST be greater than zero.
     * - There MUST be claimable withdrawals for the given account.
     *
     * @custom:effects
     * - Emits a `Claimed` event.
     */
    function claim(address account, address recipient, uint256 maxAmount)
        external
        returns (uint256 amount);

    function transferPendingAssets(address recipient, uint256 assets) external;

    function claimer() external view returns (address);
}
