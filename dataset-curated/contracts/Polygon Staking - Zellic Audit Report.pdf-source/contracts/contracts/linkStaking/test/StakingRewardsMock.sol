// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../core/interfaces/IERC677.sol";

/**
 * @title Staking Rewards Mock
 * @dev Mocks contract for testing
 */
contract StakingRewardsMock {
    using SafeERC20 for IERC677;

    IERC677 public token;

    mapping(address => uint256) public rewards;

    constructor(address _token) {
        token = IERC677(_token);
    }

    function getReward(address _staker) external view returns (uint256) {
        return rewards[_staker];
    }

    function claimReward() external {
        if (rewards[msg.sender] != 0) {
            token.safeTransfer(msg.sender, rewards[msg.sender]);
            rewards[msg.sender] = 0;
        }
    }

    function setReward(address _staker, uint256 _amount) external {
        rewards[_staker] = _amount;
    }
}
