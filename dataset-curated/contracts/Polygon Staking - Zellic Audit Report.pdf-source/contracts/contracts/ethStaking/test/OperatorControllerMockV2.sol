// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./OperatorControllerMock.sol";

/**
 * @title Operator Controller Mock V2
 * @notice Mocks contract upgrade for testing
 */
contract OperatorControllerMockV2 is OperatorControllerMock {
    function contractVersion() external pure returns (uint256) {
        return 2;
    }
}
