// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IStakingRewardsPool.sol";

interface IStakingPool is IStakingRewardsPool {
    function deposit(address _account, uint256 _amount, bytes[] calldata _data) external;

    function withdraw(
        address _account,
        address _receiver,
        uint256 _amount,
        bytes[] calldata _data
    ) external;

    function strategyDeposit(uint256 _index, uint256 _amount, bytes calldata _data) external;

    function strategyWithdraw(uint256 _index, uint256 _amount, bytes calldata _data) external;

    function updateStrategyRewards(uint256[] memory _strategyIdxs, bytes memory _data) external;

    function getMaxDeposits() external view returns (uint256);

    function addStrategy(address _strategy) external;

    function removeStrategy(uint256 _index) external;

    function reorderStrategies(uint256[] calldata _newOrder) external;

    function getStrategies() external view returns (address[] memory);

    function setPoolIndex(uint16 _poolIndex) external;

    function canDeposit() external view returns (uint256);

    function token() external view returns (address);

    function poolIndex() external view returns (uint16);

    function canWithdraw() external view returns (uint256);

    function getStrategyDepositRoom() external view returns (uint256);

    function getUnusedDeposits() external view returns (uint256);

    function burn(uint256 _amount) external;
}
