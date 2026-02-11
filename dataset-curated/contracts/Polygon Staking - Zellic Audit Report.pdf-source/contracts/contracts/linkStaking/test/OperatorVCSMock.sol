// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IOperatorVault.sol";

/**
 * @title Operator VCS Mock
 * @notice Mocks contract for testing
 */
contract OperatorVCSMock {
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 public operatorRewardPercentage;
    uint256 public withdrawalPercentage;

    IOperatorVault public vault;

    constructor(address _token, uint256 _operatorRewardPercentage, uint256 _withdrawalPercentage) {
        token = IERC20(_token);
        operatorRewardPercentage = _operatorRewardPercentage;
        withdrawalPercentage = _withdrawalPercentage;
    }

    function deposit(uint256 _amount) external {
        token.transferFrom(msg.sender, address(this), _amount);
        vault.deposit(_amount);
    }

    function withdraw(uint256 _amount) external {
        vault.withdraw(_amount);
        token.safeTransfer(msg.sender, _amount);
    }

    function unbond() external {
        vault.unbond();
    }

    function withdrawOperatorRewards(
        address _receiver,
        uint256 _amount
    ) external returns (uint256) {
        uint256 withdrawalAmount = (_amount * withdrawalPercentage) / 10000;
        return withdrawalAmount;
    }

    function updateDeposits(
        uint256 _minRewards,
        address _rewardsReceiver
    ) external returns (uint256, uint256, uint256) {
        return vault.updateDeposits(_minRewards, _rewardsReceiver);
    }

    function addVault(address _vault) external {
        vault = IOperatorVault(_vault);
        token.approve(_vault, type(uint256).max);
    }

    function removeVault() external returns (uint256, uint256) {
        return vault.exitVault();
    }

    function setWithdrawalPercentage(uint256 _withdrawalPercentage) external {
        withdrawalPercentage = _withdrawalPercentage;
    }
}
