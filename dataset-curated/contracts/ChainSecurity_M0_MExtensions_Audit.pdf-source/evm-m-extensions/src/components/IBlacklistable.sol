// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title Blacklistable interface.
 * @author M0 Labs
 */
interface IBlacklistable {
    /* ============ Events ============ */

    /**
     * @notice Emitted when an account is blacklisted.
     * @param account The address of the blacklisted account.
     * @param timestamp The timestamp at which the account was blacklisted.
     */
    event Blacklisted(address indexed account, uint256 timestamp);

    /**
     * @notice Emitted when an account is unblacklisted.
     * @param account The address of the unblacklisted account.
     * @param timestamp The timestamp at which the account was unblacklisted.
     */
    event Unblacklisted(address indexed account, uint256 timestamp);

    /* ============ Errors ============ */

    /**
     * @notice Emitted when a blacklisted account attempts to interact with the contract.
     * @param account The address of the blacklisted account.
     */
    error AccountBlacklisted(address account);

    /**
     * @notice Emitted when trying to unblacklist a non-blacklisted account.
     * @param account The address of the account that is not blacklisted.
     */
    error AccountNotBlacklisted(address account);

    /// @notice Emitted if no blacklist manager is set.
    error ZeroBlacklistManager();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Blacklists an account.
     * @dev MUST only be callable by the BLACKLIST_MANAGER_ROLE.
     * @dev SHOULD revert if the account is already blacklisted.
     * @param account The address of the account to blacklist.
     */
    function blacklist(address account) external;

    /**
     * @notice Blacklists multiple accounts.
     * @dev MUST only be callable by the BLACKLIST_MANAGER_ROLE.
     * @dev SHOULD revert if any of the accounts are already blacklisted.
     * @param accounts The list of addresses to blacklist.
     */
    function blacklistAccounts(address[] calldata accounts) external;

    /**
     * @notice Unblacklists an account.
     * @dev MUST only be callable by the BLACKLIST_MANAGER_ROLE.
     * @dev SHOULD revert if the account is not blacklisted.
     * @param account The address of the account to unblacklist.
     */
    function unblacklist(address account) external;

    /**
     * @notice Unblacklists multiple accounts.
     * @dev MUST only be callable by the BLACKLIST_MANAGER_ROLE.
     * @dev SHOULD revert if any of the accounts are not blacklisted.
     * @param accounts The list of addresses to unblacklist.
     */
    function unblacklistAccounts(address[] calldata accounts) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can manage the blacklist.
    function BLACKLIST_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns whether an account is blacklisted or not.
     * @param account The address of the account to check.
     * @return True if the account is blacklisted, false otherwise.
     */
    function isBlacklisted(address account) external view returns (bool);
}
