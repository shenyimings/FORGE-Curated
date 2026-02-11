// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RewardsReceiver
 * @notice Receives rewards to be distributed to the ETH staking strategy
 */
contract RewardsReceiver is Ownable {
    address payable public immutable ethStakingStrategy;
    uint256 public minWithdrawalAmount;
    uint256 public maxWithdrawalAmount;

    event RewardsReceived(uint256 amount);
    event RewardsWithdrawn(uint256 amount);
    event SetWithdrawalLimits(uint256 min, uint256 max);

    constructor(
        address _ethStakingStrategy,
        uint256 _minWithdrawalAmount,
        uint256 _maxWithdrawalAmount
    ) {
        ethStakingStrategy = payable(_ethStakingStrategy);
        minWithdrawalAmount = _minWithdrawalAmount;
        maxWithdrawalAmount = _maxWithdrawalAmount;
    }

    receive() external payable {
        emit RewardsReceived(msg.value);
    }

    /**
     * @notice Withdraws rewards to the ETH staking strategy
     */
    function withdraw() external returns (uint256) {
        require(msg.sender == ethStakingStrategy, "Sender is not ETH staking strategy");

        uint256 balance = address(this).balance;
        uint256 value;

        if (balance < minWithdrawalAmount) {
            value = 0;
        } else if (balance > maxWithdrawalAmount) {
            value = maxWithdrawalAmount;
        } else {
            value = balance;
        }

        if (value > 0) {
            (bool success, ) = ethStakingStrategy.call{value: value}("");
            require(success, "ETH transfer failed");
            emit RewardsWithdrawn(value);
        }

        return value;
    }

    /**
     * @notice Sets the minimum and maximum amount that can be withdrawn per transaction
     * @param _minWithdrawalAmount minimum amount
     * @param _maxWithdrawalAmount maximum amount
     */
    function setWithdrawalLimits(
        uint256 _minWithdrawalAmount,
        uint256 _maxWithdrawalAmount
    ) external onlyOwner {
        require(
            _minWithdrawalAmount <= _maxWithdrawalAmount,
            "min must be less than or equal to max"
        );
        minWithdrawalAmount = _minWithdrawalAmount;
        maxWithdrawalAmount = _maxWithdrawalAmount;
        emit SetWithdrawalLimits(_minWithdrawalAmount, _maxWithdrawalAmount);
    }
}
