// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IL1Strategy {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function updateDeposits(
        uint32 _l2Gas,
        uint256 _l2Fee
    ) external payable returns (uint256, uint256, address[] memory, uint256[] memory);

    function depositQueuedTokens(uint256[] calldata _vaults, uint256[] calldata _amounts) external;

    function getVaults() external view returns (address[] memory);

    function rewardRecipient() external view returns (address);

    function operatorRewardPercentage() external view returns (uint256);

    function getVaultDepositMax() external view returns (uint256);

    function getVaultDepositMin() external view returns (uint256);

    function canWithdraw() external view returns (uint256);
}
