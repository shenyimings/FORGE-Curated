// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

/// @title Interface of the Masterchef contract
/// @author vfat.tools
/// @notice Basic Masterchef interface
interface IMasterchef {
    function deposit(uint256 _pid, uint256 _amount) external;

    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(
        uint256 _pid
    ) external;

    function userInfo(
        uint256 poolId,
        address user
    ) external view returns (uint256 amount, uint256 rewardDebt);
}
