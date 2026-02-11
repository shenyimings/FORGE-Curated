// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../PolygonVault.sol";

/**
 * @title Polygon Vault V2 Mock
 * @notice Mocks V2 upgrade for testing
 */
contract PolygonVaultV2Mock is PolygonVault {
    uint256 public version;

    function initializeV2(uint256 _version) public reinitializer(2) {
        version = _version;
    }
}
