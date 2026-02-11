// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Polygon Stake Manager Mock
 * @notice Mocks contract for testing
 */
contract PolygonStakeManagerMock {
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public withdrawalDelay;

    constructor(address _token, uint256 _withdrawalDelay) {
        token = IERC20(_token);
        withdrawalDelay = _withdrawalDelay;
    }

    function epoch() external view returns (uint256) {
        return block.timestamp;
    }

    function deposit(address _account, uint256 _amount) external {
        token.safeTransferFrom(_account, address(this), _amount);
    }

    function withdraw(address _account, uint256 _amount) external {
        token.safeTransfer(_account, _amount);
    }
}
