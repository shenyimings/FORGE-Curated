// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../core/interfaces/IERC677.sol";
import "../../core/interfaces/IERC677Receiver.sol";

/**
 * @title Staking Mock
 * @dev Mocks contract for testing
 */
contract StakingMockV1 is IERC677Receiver {
    IERC677 public token;

    mapping(address => uint256) public stakedBalances;
    address public migration;

    uint256 public baseReward;
    uint256 public delegationReward;

    bool public active;
    bool public paused;

    constructor(address _token) {
        token = IERC677(_token);
        active = true;
    }

    function onTokenTransfer(address _sender, uint256 _value, bytes calldata) external {
        require(msg.sender == address(token), "has to be token");
        stakedBalances[_sender] += _value;
    }

    function getCommunityStakerLimits() external pure returns (uint256, uint256) {
        return (10 ether, 7000 ether);
    }

    function getOperatorLimits() external pure returns (uint256, uint256) {
        return (10 ether, 50000 ether);
    }

    function getMaxPoolSize() external pure returns (uint256) {
        return 25000000 ether;
    }

    function getTotalStakedAmount() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function setActive(bool _active) external {
        active = _active;
    }

    function isActive() external view returns (bool) {
        return active;
    }

    function isOperator(address) external pure returns (bool) {
        return true;
    }

    function getStake(address staker) external view returns (uint256) {
        return stakedBalances[staker];
    }

    function setMigration(address _migration) external {
        migration = _migration;
    }

    function migrate(bytes calldata) external {
        token.transferAndCall(
            migration,
            stakedBalances[msg.sender] + baseReward + delegationReward,
            abi.encode(msg.sender)
        );
    }

    function setBaseReward(uint256 _amount) external {
        baseReward = _amount;
    }

    function getBaseReward(address) external view returns (uint256) {
        return baseReward;
    }

    function setDelegationReward(uint256 _amount) external {
        delegationReward = _amount;
    }

    function getDelegationReward(address) external view returns (uint256) {
        return delegationReward;
    }

    function getMigrationTarget() external view returns (address) {
        return migration;
    }

    function setPaused(bool _paused) external {
        paused = _paused;
    }

    function isPaused() external view returns (bool) {
        return paused;
    }

    function raiseAlert() external {
        token.transfer(msg.sender, 100 ether);
    }
}
