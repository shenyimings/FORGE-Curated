// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/**
 * @title MVM Discount Oracle Mock
 * @dev Mocks contract for testing
 */
contract MVM_DiscountOracleMock {
    function getMinL2Gas() external view returns (uint256) {
        return 200000;
    }

    function getDiscount() external view returns (uint256) {
        return 2;
    }
}
