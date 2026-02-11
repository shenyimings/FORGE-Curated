// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IFundFlowController {
    function claimPeriodActive() external view returns (bool);

    function getDepositData(uint256 _amount) external view returns (bytes[] memory);

    function updateOperatorVaultGroupAccounting(uint256[] calldata _vaultGroups) external;
}
