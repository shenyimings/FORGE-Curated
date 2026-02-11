// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IVault.sol";

interface IOperatorVault is IVault {
    function getPendingRewards() external view returns (uint256);

    function updateDeposits(
        uint256 _minRewards,
        address _rewardsReceiver
    ) external returns (uint256, uint256, uint256);

    function exitVault() external returns (uint256, uint256);

    function setOperator(address _operator) external;

    function setRewardsReceiver(address _rewardsReceiver) external;
}
