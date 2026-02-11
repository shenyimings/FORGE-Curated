// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/**
 * @title OVM Gas Price Oracle Mock
 * @dev Mocks contract for testing
 */
contract OVM_GasPriceOracleMock {
    function minErc20BridgeCost() external view returns (uint256) {
        return 0.5 ether;
    }
}
