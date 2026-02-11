// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract MockAaveDataProvider {
    uint256 private variableBorrowRate;

    function setVariableBorrowRate(uint256 _variableBorrowRate) external {
        variableBorrowRate = _variableBorrowRate;
    }

    function getVariableBorrowRate() external view returns (uint256) {
        return variableBorrowRate;
    }

    function getReserveData(address)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint40
        )
    {
        return (0, 0, 0, 0, 0, 0, variableBorrowRate, 0, 0, 0, 0, uint40(block.timestamp));
    }
}
