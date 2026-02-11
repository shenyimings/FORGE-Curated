// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface ISequencerVault {
    function getTotalDeposits() external view returns (uint256);

    function getPrincipalDeposits() external view returns (uint256);

    function getPendingRewards() external view returns (uint256);

    function updateDeposits(
        uint256 _minRewards,
        uint32 _l2Gas
    ) external payable returns (uint256, uint256, uint256);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function canWithdraw() external view returns (uint256);

    function rewardsReceiver() external view returns (address);

    function initiateExit() external;

    function finalizeExit() external;

    function exitDelayEndTime() external view returns (uint64);

    function upgradeToAndCall(address _newImplementation, bytes memory _data) external;

    function upgradeTo(address _newImplementation) external;
}
