// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IVault {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function unbond() external;

    function getTotalDeposits() external view returns (uint256);

    function getPrincipalDeposits() external view returns (uint256);

    function getRewards() external view returns (uint256);

    function claimPeriodActive() external view returns (bool);

    function isRemoved() external view returns (bool);

    function migrate(bytes calldata _data) external;

    function delegate(address _to, bytes32 _rights, bool _enable) external;

    function withdrawTokenRewards(address[] calldata _tokens) external;

    function upgradeToAndCall(address _newImplementation, bytes memory _data) external;

    function upgradeTo(address _newImplementation) external;
}
