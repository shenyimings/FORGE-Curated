// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/vaults/IVaultControlStorage.sol";

abstract contract VaultControlStorage is IVaultControlStorage, Initializable, ContextUpgradeable {
    bytes32 private immutable storageSlotRef;

    constructor(bytes32 name_, uint256 version_) {
        storageSlotRef = keccak256(
            abi.encode(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            "mellow.simple-lrt.storage.VaultControlStorage", name_, version_
                        )
                    )
                ) - 1
            )
        ) & ~bytes32(uint256(0xff));
    }

    /**
     * @notice Initializes the Vault storage with the provided settings for limit, pause states, and whitelist.
     * @param _limit The initial value for the Vault's deposit limit.
     * @param _depositPause The initial state for the `depositPause` flag.
     * @param _withdrawalPause The initial state for the `withdrawalPause` flag.
     * @param _depositWhitelist The initial state for the `depositWhitelist` flag.
     *
     * @custom:requirements
     * - This function MUST not be called more than once; it is intended for one-time initialization.
     *
     * @custom:effects
     * - Sets the provided limit, pause states, and whitelist state in the Vault's storage.
     * - Emits the `LimitSet` event after the limit is set.
     * - Emits the `DepositPauseSet` event after the deposit pause state is set.
     * - Emits the `WithdrawalPauseSet` event after the withdrawal pause state is set.
     * - Emits the `DepositWhitelistSet` event after the deposit whitelist state is set.
     *
     * @dev This function is protected by the `onlyInitializing` modifier to ensure it is only called during the contract's initialization phase.
     */
    function __initializeVaultControlStorage(
        uint256 _limit,
        bool _depositPause,
        bool _withdrawalPause,
        bool _depositWhitelist
    ) internal onlyInitializing {
        _setLimit(_limit);
        _setDepositPause(_depositPause);
        _setWithdrawalPause(_withdrawalPause);
        _setDepositWhitelist(_depositWhitelist);
    }
    /// @inheritdoc IVaultControlStorage

    function depositPause() public view returns (bool) {
        return _vaultStorage().depositPause;
    }

    /// @inheritdoc IVaultControlStorage
    function withdrawalPause() public view returns (bool) {
        return _vaultStorage().withdrawalPause;
    }

    /// @inheritdoc IVaultControlStorage
    function limit() public view returns (uint256) {
        return _vaultStorage().limit;
    }

    /// @inheritdoc IVaultControlStorage
    function depositWhitelist() public view returns (bool) {
        return _vaultStorage().depositWhitelist;
    }

    /// @inheritdoc IVaultControlStorage
    function isDepositorWhitelisted(address account) public view returns (bool) {
        return _vaultStorage().isDepositorWhitelisted[account];
    }

    /**
     * @notice Sets a new `limit` for the Vault.
     * @param _limit The new limit for the Vault.
     *
     * @custom:effects
     * - Updates the Vault's `limit` in storage.
     * - Emits the `LimitSet` event with the new limit, current timestamp, and the caller's address.
     */
    function _setLimit(uint256 _limit) internal {
        Storage storage s = _vaultStorage();
        s.limit = _limit;
        emit LimitSet(_limit, block.timestamp, _msgSender());
    }

    /**
     * @notice Sets a new `depositPause` state for the Vault.
     * @param _paused The new value for the `depositPause` state.
     *
     * @custom:effects
     * - Updates the Vault's `depositPause` state in storage.
     * - Emits the `DepositPauseSet` event with the new pause state, current timestamp, and the caller's address.
     */
    function _setDepositPause(bool _paused) internal {
        Storage storage s = _vaultStorage();
        s.depositPause = _paused;
        emit DepositPauseSet(_paused, block.timestamp, _msgSender());
    }

    /**
     * @notice Sets a new `withdrawalPause` state for the Vault.
     * @param _paused The new value for the `withdrawalPause` state.
     *
     * @custom:effects
     * - Updates the Vault's `withdrawalPause` state in storage.
     * - Emits the `WithdrawalPauseSet` event with the new pause state, current timestamp, and the caller's address.
     */
    function _setWithdrawalPause(bool _paused) internal {
        Storage storage s = _vaultStorage();
        s.withdrawalPause = _paused;
        emit WithdrawalPauseSet(_paused, block.timestamp, _msgSender());
    }

    /**
     * @notice Sets a new `depositWhitelist` state for the Vault.
     * @param _status The new value for the `depositWhitelist` state.
     *
     * @custom:effects
     * - Updates the Vault's `depositWhitelist` state in storage.
     * - Emits the `DepositWhitelistSet` event with the new whitelist status, current timestamp, and the caller's address.
     */
    function _setDepositWhitelist(bool _status) internal {
        Storage storage s = _vaultStorage();
        s.depositWhitelist = _status;
        emit DepositWhitelistSet(_status, block.timestamp, _msgSender());
    }

    /**
     * @notice Sets a new whitelist `status` for the given `account`.
     * @param account The address of the account to update.
     * @param status The new whitelist status for the account.
     *
     * @custom:effects
     * - Updates the whitelist status of the `account` in storage.
     * - Emits the `DepositorWhitelistStatusSet` event with the account, new status, current timestamp, and the caller's address.
     */
    function _setDepositorWhitelistStatus(address account, bool status) internal {
        Storage storage s = _vaultStorage();
        s.isDepositorWhitelisted[account] = status;
        emit DepositorWhitelistStatusSet(account, status, block.timestamp, _msgSender());
    }

    /**
     * @notice Accesses the storage slot for the Vault's data.
     * @return $ A reference to the `Storage` struct for the Vault.
     *
     * @dev This function uses inline assembly to access a predefined storage slot.
     */
    function _vaultStorage() private view returns (Storage storage $) {
        bytes32 slot = storageSlotRef;
        assembly {
            $.slot := slot
        }
    }
}
