// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IWithdrawalPool {
    function getTotalQueuedWithdrawals() external view returns (uint256);

    function minWithdrawalAmount() external view returns (uint256);

    function getAccountTotalQueuedWithdrawals(address _account) external view returns (uint256);

    function getFinalizedWithdrawalIdsByOwner(
        address _account
    ) external view returns (uint256[] memory, uint256);

    function getBatchIds(uint256[] memory _withdrawalIds) external view returns (uint256[] memory);

    function deposit(uint256 _amount) external;

    function withdraw(uint256[] calldata _withdrawalIds, uint256[] calldata _batchIds) external;

    function queueWithdrawal(address _account, uint256 _amount) external;

    function performUpkeep(bytes calldata _performData) external;

    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory);
}
