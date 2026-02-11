// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../SequencerVault.sol";

/**
 * @title Sequencer Vault V2 Mock
 * @notice Mocks contract for testing
 */
contract SequencerVaultV2Mock is SequencerVault {
    uint256 public version;

    function initializeV2(uint256 _version) public reinitializer(2) {
        version = _version;
    }

    function isUpgraded() external view returns (bool) {
        return true;
    }

    function getVersion() external view returns (uint256) {
        return version;
    }
}
