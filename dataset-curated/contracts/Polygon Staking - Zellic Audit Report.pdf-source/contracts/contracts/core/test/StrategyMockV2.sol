// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./StrategyMock.sol";

/**
 * @title Strategy Mock V2
 * @notice Mocks contract upgrade for testing
 */
contract StrategyMockV2 is StrategyMock {
    function contractVersion() external pure returns (uint256) {
        return 2;
    }
}
