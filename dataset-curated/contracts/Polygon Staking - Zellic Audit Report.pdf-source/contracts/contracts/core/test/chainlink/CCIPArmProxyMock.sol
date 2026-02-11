// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

/**
 * @title CCIP ARMProxy Mock
 * @notice Mocks CCIP contract for testing
 */
contract CCIPArmProxyMock {
    function isCursed() external returns (bool) {
        return false;
    }
}
