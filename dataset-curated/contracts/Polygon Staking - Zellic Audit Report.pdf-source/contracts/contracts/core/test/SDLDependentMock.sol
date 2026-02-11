// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

/**
 * @title SDL Dependent
 * @notice Mocks contract for testing
 */
contract SDLDependentMock {
    mapping(address => uint256) public balances;

    function updateSDLBalance(address _account, uint256 _balance) external {
        balances[_account] = _balance;
    }
}
