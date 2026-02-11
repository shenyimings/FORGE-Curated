// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Imports.sol";

contract MockVaultControlStorage is VaultControlStorage {
    constructor(bytes32 name, uint256 version) VaultControlStorage(name, version) {}

    function initializeVaultControlStorage(
        uint256 _limit,
        bool _depositPause,
        bool _withdrawalPause,
        bool _depositWhitelist
    ) external initializer {
        __initializeVaultControlStorage(_limit, _depositPause, _withdrawalPause, _depositWhitelist);
    }

    function setLimit(uint256 _limit) external {
        _setLimit(_limit);
    }

    function setDepositPause(bool _paused) external {
        _setDepositPause(_paused);
    }

    function setWithdrawalPause(bool _paused) external {
        _setWithdrawalPause(_paused);
    }

    function setDepositWhitelist(bool _status) external {
        _setDepositWhitelist(_status);
    }

    function setDepositorWhitelistStatus(address account, bool status) external {
        _setDepositorWhitelistStatus(account, status);
    }

    function test() private pure {}
}
