// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Imports.sol";

contract MockERC4626Vault is ERC4626Vault {
    constructor(bytes32 name_, uint256 version_) VaultControlStorage(name_, version_) {}

    function initializeERC4626(
        address _admin,
        uint256 _limit,
        bool _depositPause,
        bool _withdrawalPause,
        bool _depositWhitelist,
        address _asset,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __initializeERC4626(
            _admin,
            _limit,
            _depositPause,
            _withdrawalPause,
            _depositWhitelist,
            _asset,
            _name,
            _symbol
        );
    }

    function test() private pure {}
}
