// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISequencerVault.sol";
import "../interfaces/IMetisLockingInfo.sol";

/**
 * @title Sequencer VCS Mock
 * @notice Mocks contract for testing
 */
contract SequencerVCSMock {
    using SafeERC20 for IERC20;

    IERC20 public token;
    IMetisLockingInfo public lockingInfo;

    uint256 public operatorRewardPercentage;

    ISequencerVault public vault;
    address public rewardRecipient;

    constructor(address _token, address _lockingInfo, uint256 _operatorRewardPercentage) {
        token = IERC20(_token);
        lockingInfo = IMetisLockingInfo(_lockingInfo);
        operatorRewardPercentage = _operatorRewardPercentage;
        rewardRecipient = address(9);
    }

    function getVaultDepositMax() external returns (uint256) {
        return lockingInfo.maxLock();
    }

    function getVaultDepositMin() external returns (uint256) {
        return lockingInfo.minLock();
    }

    function deposit(uint256 _amount) external {
        token.transferFrom(msg.sender, address(this), _amount);
        vault.deposit(_amount);
    }

    function withdraw(uint256 _amount) external {
        vault.withdraw(_amount);
        token.transfer(msg.sender, _amount);
    }

    function updateDeposits(
        uint256 _minRewards
    ) external payable returns (uint256, uint256, uint256) {
        return vault.updateDeposits{value: msg.value}(_minRewards, 0);
    }

    function initiateExit() external {
        vault.initiateExit();
    }

    function finalizeExit() external {
        vault.finalizeExit();
    }

    function addVault(address _vault) external {
        vault = ISequencerVault(_vault);
        token.approve(_vault, type(uint256).max);
    }

    receive() external payable {}
}
