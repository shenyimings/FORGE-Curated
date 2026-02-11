// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Imports.sol";

contract MockVaultControl is VaultControl {
    constructor(bytes32 name, uint256 version) VaultControlStorage(name, version) {}

    function initializeVaultControl(
        address _admin,
        uint256 _limit,
        bool _depositPause,
        bool _withdrawalPause,
        bool _depositWhitelist
    ) public initializer {
        __initializeVaultControl(_admin, _limit, _depositPause, _withdrawalPause, _depositWhitelist);
    }

    function test() private pure {}
}
