// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

/**
 * @title SDL Pool Mock
 * @notice Mocks contract for testing
 */
contract SDLPoolMock {
    mapping(address => uint256) public effectiveBalances;

    function effectiveBalanceOf(address _account) external view returns (uint256) {
        return effectiveBalances[_account];
    }

    function setEffectiveBalance(address _account, uint256 _amount) public {
        effectiveBalances[_account] = _amount;
    }
}
