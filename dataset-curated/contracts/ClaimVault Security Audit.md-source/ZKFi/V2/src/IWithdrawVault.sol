// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

interface IWithdrawVault {
    function transfer(address, address, uint256) external;
    function addSupportedToken(address) external;
    function setVault(address) external;
    function getSupportedTokens() external view returns (address[] memory);
    function getBalance(address) external view returns (uint256);
    function emergencyWithdraw(address, address, uint) external;
    function transferToCeffu(address token, uint amount)external;
}