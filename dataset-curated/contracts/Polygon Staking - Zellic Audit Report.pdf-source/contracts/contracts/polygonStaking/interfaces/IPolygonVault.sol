// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IPolygonVault {
    function deposit(uint256 _amount) external;

    function withdraw() external;

    function unbond(uint256 _amount) external;

    function restakeRewards() external;

    function withdrawRewards() external;

    function getTotalDeposits() external view returns (uint256);

    function getPrincipalDeposits() external view returns (uint256);

    function getQueuedWithdrawals() external view returns (uint256);

    function getRewards() external view returns (uint256);

    function isUnbonding() external view returns (bool);

    function isWithdrawable() external view returns (bool);

    function upgradeToAndCall(address _newImplementation, bytes memory _data) external;

    function upgradeTo(address _newImplementation) external;

    function minRewardClaimAmount() external view returns (uint256);
}
