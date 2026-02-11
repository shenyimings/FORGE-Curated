// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IWETH9 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    /// @param amount The amount of wrapped ether to withdraw
    function withdraw(uint256 amount) external;
}
