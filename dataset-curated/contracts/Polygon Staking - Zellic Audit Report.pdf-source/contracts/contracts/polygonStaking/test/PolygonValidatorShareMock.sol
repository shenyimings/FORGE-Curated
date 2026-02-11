// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../interfaces/IPolygonStakeManager.sol";

interface IPolygonStakeManagerMock is IPolygonStakeManager {
    function deposit(address _account, uint256 _amount) external;

    function withdraw(address _account, uint256 _amount) external;
}

/**
 * @title Polygon Validator Share Mock
 * @notice Mocks contract for testing
 */
contract PolygonValidatorShareMock {
    uint256 constant EXCHANGE_RATE_PRECISION = 10 ** 29;

    struct DelegatorUnbond {
        uint256 shares;
        uint256 withdrawEpoch;
    }

    uint256 public validatorId = 8;

    IPolygonStakeManagerMock public stakeManager;
    mapping(address => uint256) private staked;
    mapping(address => uint256) private liquidRewards;
    mapping(address => DelegatorUnbond) public unbonds;

    uint256 public minAmount = 1 ether;

    error InsufficientBalance();
    error IncompleteWithdrawalPeriod();
    error NoRewards();

    constructor(address _stakeManager) {
        stakeManager = IPolygonStakeManagerMock(_stakeManager);
    }

    function buyVoucherPOL(uint256 _amount, uint256) external returns (uint256) {
        stakeManager.deposit(msg.sender, _amount);
        staked[msg.sender] += _amount;

        uint256 rewards = liquidRewards[msg.sender];
        if (rewards != 0) {
            delete liquidRewards[msg.sender];
            stakeManager.withdraw(msg.sender, rewards);
        }

        return _amount;
    }

    function sellVoucherPOL(uint256 _claimAmount, uint256) external {
        if (staked[msg.sender] < _claimAmount) revert InsufficientBalance();

        staked[msg.sender] -= _claimAmount;
        unbonds[msg.sender].shares += _claimAmount;
        unbonds[msg.sender].withdrawEpoch = block.timestamp;

        uint256 rewards = liquidRewards[msg.sender];
        if (rewards != 0) {
            delete liquidRewards[msg.sender];
            stakeManager.withdraw(msg.sender, rewards);
        }
    }

    function unstakeClaimTokensPOL() external {
        DelegatorUnbond memory unbond = unbonds[msg.sender];

        uint256 shares = unbond.shares;
        if (
            unbond.withdrawEpoch + stakeManager.withdrawalDelay() > stakeManager.epoch() ||
            shares == 0
        ) revert IncompleteWithdrawalPeriod();

        delete unbonds[msg.sender];
        stakeManager.withdraw(msg.sender, shares);
    }

    function restakePOL() external returns (uint256, uint256) {
        uint256 rewards = liquidRewards[msg.sender];
        if (rewards == 0) revert NoRewards();

        delete liquidRewards[msg.sender];
        staked[msg.sender] += rewards;
        return (rewards, rewards);
    }

    function withdrawRewardsPOL() external {
        uint256 rewards = liquidRewards[msg.sender];
        if (rewards < minAmount) revert NoRewards();

        delete liquidRewards[msg.sender];
        stakeManager.withdraw(msg.sender, rewards);
    }

    function getLiquidRewards(address _user) external view returns (uint256) {
        return liquidRewards[_user];
    }

    function balanceOf(address _user) external view returns (uint256) {
        return staked[_user];
    }

    function exchangeRate() external pure returns (uint256) {
        return EXCHANGE_RATE_PRECISION;
    }

    function withdrawExchangeRate() external pure returns (uint256) {
        return EXCHANGE_RATE_PRECISION;
    }

    function addReward(address _user, uint256 _amount) external {
        liquidRewards[_user] += _amount;
        stakeManager.deposit(msg.sender, _amount);
    }

    function removeReward(address _user, uint256 _amount) external {
        liquidRewards[_user] -= _amount;
        stakeManager.withdraw(msg.sender, _amount);
    }
}
