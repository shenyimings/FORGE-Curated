// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

/**
 * @title Withdrawal Pool Mock
 * @notice Mocks contract for testing
 */
contract WithdrawalPoolMock {
    uint256 private totalQueuedWithdrawals;

    function getTotalQueuedWithdrawals() external view returns (uint256) {
        return totalQueuedWithdrawals;
    }

    function setTotalQueuedWithdrawals(uint256 _totalQueuedWithdrawals) external {
        totalQueuedWithdrawals = _totalQueuedWithdrawals;
    }

    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        return (totalQueuedWithdrawals != 0, "0x");
    }

    function performUpkeep(bytes calldata) external {}
}
