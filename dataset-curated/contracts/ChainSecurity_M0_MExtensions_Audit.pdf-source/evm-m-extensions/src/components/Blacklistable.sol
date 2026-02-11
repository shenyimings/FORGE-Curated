// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import {
    AccessControlUpgradeable
} from "../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IBlacklistable } from "./IBlacklistable.sol";

abstract contract BlacklistableStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.Blacklistable
    struct BlacklistableStorageStruct {
        mapping(address account => bool isBlacklisted) isBlacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.Blacklistable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _BLACKLISTABLE_STORAGE_LOCATION =
        0x6ca6e63f3105e14b3bf80a97d5387f4eb60faf3718a872ce718e736bc3754100;

    function _getBlacklistableStorageLocation() internal pure returns (BlacklistableStorageStruct storage $) {
        assembly {
            $.slot := _BLACKLISTABLE_STORAGE_LOCATION
        }
    }
}

/**
 * @title Blacklistable
 * @notice Upgradeable contract that allows for the blacklisting of accounts.
 * @dev This contract is used to prevent certain accounts from interacting with the contract.
 * @author M0 Labs
 */
abstract contract Blacklistable is IBlacklistable, BlacklistableStorageLayout, AccessControlUpgradeable {
    /* ============ Variables ============ */

    /// @inheritdoc IBlacklistable
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the contract with the given blacklist manager.
     * @param blacklistManager The address of a blacklist manager.
     */
    function __Blacklistable_init(address blacklistManager) internal onlyInitializing {
        if (blacklistManager == address(0)) revert ZeroBlacklistManager();
        _grantRole(BLACKLIST_MANAGER_ROLE, blacklistManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IBlacklistable
    function blacklist(address account) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _blacklist(_getBlacklistableStorageLocation(), account);
    }

    /// @inheritdoc IBlacklistable
    function blacklistAccounts(address[] calldata accounts) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        BlacklistableStorageStruct storage $ = _getBlacklistableStorageLocation();

        for (uint256 i; i < accounts.length; ++i) {
            _blacklist($, accounts[i]);
        }
    }

    /// @inheritdoc IBlacklistable
    function unblacklist(address account) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _unblacklist(_getBlacklistableStorageLocation(), account);
    }

    /// @inheritdoc IBlacklistable
    function unblacklistAccounts(address[] calldata accounts) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        BlacklistableStorageStruct storage $ = _getBlacklistableStorageLocation();

        for (uint256 i; i < accounts.length; ++i) {
            _unblacklist($, accounts[i]);
        }
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IBlacklistable
    function isBlacklisted(address account) public view returns (bool) {
        return _getBlacklistableStorageLocation().isBlacklisted[account];
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @notice Internal function that blacklists an account.
     * @param $ The storage location of the blacklistable contract.
     * @param account The account to blacklist.
     */
    function _blacklist(BlacklistableStorageStruct storage $, address account) internal virtual {
        _revertIfBlacklisted($, account);

        $.isBlacklisted[account] = true;

        emit Blacklisted(account, block.timestamp);
    }

    /**
     * @notice Internal function that unblacklists an account.
     * @param $ The storage location of the blacklistable contract.
     * @param account The account to unblacklist.
     */
    function _unblacklist(BlacklistableStorageStruct storage $, address account) internal {
        _revertIfNotBlacklisted($, account);

        $.isBlacklisted[account] = false;

        emit Unblacklisted(account, block.timestamp);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @notice Internal function that reverts if an account is blacklisted.
     * @param $ The storage location of the blacklistable contract.
     * @param account The account to check.
     */
    function _revertIfBlacklisted(BlacklistableStorageStruct storage $, address account) internal view {
        if ($.isBlacklisted[account]) revert AccountBlacklisted(account);
    }

    /**
     * @notice Internal function that reverts if an account is blacklisted.
     * @param $ The storage location of the blacklistable contract.
     * @param account The account to check.
     */
    function _revertIfNotBlacklisted(BlacklistableStorageStruct storage $, address account) internal view {
        if (!$.isBlacklisted[account]) revert AccountNotBlacklisted(account);
    }
}
