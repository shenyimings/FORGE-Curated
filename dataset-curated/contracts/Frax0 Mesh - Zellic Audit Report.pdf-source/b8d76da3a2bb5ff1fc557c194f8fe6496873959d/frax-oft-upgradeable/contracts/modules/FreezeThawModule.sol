pragma solidity ^0.8.0;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title FreezeThawModule
 * @dev Contract module that allows freezing and thawing of accounts.
 */
abstract contract FreezeThawModule {

    using EnumerableSet for EnumerableSet.AddressSet;

    struct FreezeThawStorage {
        EnumerableSet.AddressSet freezers;
        EnumerableSet.AddressSet frozen;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.FreezeThawModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FreezeThawStorageLocation = 0xf6192aebe04228448ed4fd2802d59c009f5324cdd6a110c65bd318373b6e1d00;

    function _getFreezeThawStorage() private pure returns (FreezeThawStorage storage $) {
        assembly {
            $.slot := FreezeThawStorageLocation
        }
    }

    /// @notice Internal helper function to freeze an account
    /// @param account The account to freeze
    /// @dev To be called externally by admin
    /// @dev Does not revert if the account is already frozen so that freezing always succeeds
    function _freeze(address account) internal virtual {
        FreezeThawStorage storage $ = _getFreezeThawStorage();
        $.frozen.add(account);
        emit AccountFrozen(account);
    }

    /// @notice Internal helper function to unfreeze an account
    /// @param account The account to unfreeze
    /// @dev To be called externally by admin
    /// @dev Does not revert if the account is not frozen so that thawing always succeeds
    function _thaw(address account) internal virtual {
        FreezeThawStorage storage $ = _getFreezeThawStorage();
        $.frozen.remove(account);
        emit AccountThawed(account);
    }

    /// @notice Internal helper function to freeze an array of accounts
    /// @param accounts The accounts to freeze
    /// @dev To be called externally by admin
    function _freezeMany(address[] memory accounts) internal virtual {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ++i) {
            _freeze(accounts[i]);
        }
    }

    /// @notice Internal helper function to unfreeze an array of accounts
    /// @param accounts The accounts to be unfrozen
    /// @dev To be called externally by admin
    function _thawMany(address[] memory accounts) internal virtual {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ++i) {
            _thaw(accounts[i]);
        }
    }

    /// @notice Add a freezer role to an account
    /// @param account The account to add as a freezer
    /// @dev To be called externally by admin
    /// @dev Reverts if the account is already a freezer
    function _addFreezer(address account) internal virtual {
        FreezeThawStorage storage $ = _getFreezeThawStorage();
        if (!$.freezers.add(account)) revert AlreadyFreezer();
        emit AddFreezer(account);
    }

    /// @notice Remove a freezer role from an account
    /// @param account The account to remove as a freezer
    /// @dev To be called externally by admin
    /// @dev Reverts if the account is not a freezer
    function _removeFreezer(address account) internal virtual {
        FreezeThawStorage storage $ = _getFreezeThawStorage();
        if (!$.freezers.remove(account)) revert NotFreezer();
        emit RemoveFreezer(account);
    }

    /// @notice Check if an account is frozen
    /// @param account The account to check
    /// @return bool True if the account is frozen, false otherwise
    function isFrozen(address account) public view virtual returns (bool) {
        FreezeThawStorage storage $ = _getFreezeThawStorage();
        return $.frozen.contains(account);
    }

    /// @notice Check if an account is an authorized freezer
    /// @param account The account to check
    /// @return bool True if the account is a freezer, false otherwise
    function isFreezer(address account) public view virtual returns (bool) {
        FreezeThawStorage storage $ =_getFreezeThawStorage();
        return $.freezers.contains(account);
    }

    /// @notice Get the list of all frozen accounts
    /// @return addres[] An array set of all frozen accounts
    function frozen() external view virtual returns (address[] memory) {
        FreezeThawStorage storage $ = _getFreezeThawStorage();
        return $.frozen.values();
    }

    /// @notice Get the list of all freezer accounts
    /// @return address[] An array set of all freezer accounts
    function freezers() external view virtual returns (address[] memory) {
        FreezeThawStorage storage $ = _getFreezeThawStorage();
        return $.freezers.values();
    }

    /* ========== EVENTS ========== */
    /// @notice Event Emitted when a freezer is aded
    /// @param account The account being added as a freezre
    event AddFreezer(address indexed account);

    /// @notice Event Emitted when a freezer is removed
    /// @param account The account being removed as a freezer
    event RemoveFreezer(address indexed account);

    /// @notice Event Emitted when an address is frozen
    /// @param account The account being frozen
    event AccountFrozen(address account);

    /// @notice Event Emitted when an address is unfrozen
    /// @param account The account being thawed
    event AccountThawed(address account);

    /* ========== ERRORS ========== */
    error AlreadyFreezer();
    error NotFreezer();
}