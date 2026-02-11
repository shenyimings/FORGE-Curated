// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

/**
 * @title ERC677 Receiver
 * @notice Mocks ERC677 receiver for testing
 */
contract ERC677ReceiverMock {
    uint256 public totalRewards;

    function onTokenTransfer(address, uint256 _value, bytes calldata) external virtual {
        totalRewards += _value;
    }
}
