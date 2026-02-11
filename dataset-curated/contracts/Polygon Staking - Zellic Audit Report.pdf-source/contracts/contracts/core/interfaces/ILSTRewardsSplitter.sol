// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface ILSTRewardsSplitter {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount, address _receiver) external;

    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory);

    function performUpkeep(bytes calldata) external;

    function principalDeposits() external view returns (uint256);

    function splitRewards() external;
}
