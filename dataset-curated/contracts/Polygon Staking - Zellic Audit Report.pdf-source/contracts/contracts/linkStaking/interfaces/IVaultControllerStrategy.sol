// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IVaultControllerStrategy {
    function getVaults() external view returns (address[] memory);

    function getVaultDepositLimits() external view returns (uint256, uint256);

    function vaultGroups(uint256 _vaultGroupIndex) external view returns (uint64, uint128);

    function globalVaultState() external view returns (uint64, uint64, uint64, uint64);

    function updateVaultGroups(
        uint256[] calldata _curGroupVaultsToUnbond,
        uint256 _curGroupTotalDepositRoom,
        uint256 _nextGroup,
        uint256 _nextGroupTotalUnbonded
    ) external;

    function totalUnbonded() external view returns (uint256);

    function vaultMaxDeposits() external view returns (uint256);

    function fundFlowController() external view returns (address);
}
