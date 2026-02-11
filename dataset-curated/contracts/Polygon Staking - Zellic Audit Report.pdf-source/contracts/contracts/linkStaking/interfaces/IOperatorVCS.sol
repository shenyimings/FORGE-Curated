// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IOperatorVCS {
    function withdrawOperatorRewards(address _receiver, uint256 _amount) external returns (uint256);

    function operatorRewardPercentage() external view returns (uint256);

    function updateVaultGroupAccounting(
        uint256[] calldata _vaultGroups,
        uint256[] calldata _totalDepositRoom,
        uint256 _totalUnbonded,
        uint256 _vaultMaxDeposits
    ) external;
}
