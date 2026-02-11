// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IStUSR {

    event Deposit(address indexed _sender, address indexed _receiver, uint256 _usrAmount, uint256 _shares);
    event Withdraw(address indexed _sender, address indexed _receiver, uint256 _usrAmount, uint256 _shares);

    error InvalidDepositAmount(uint256 _usrAmount);

    function deposit(uint256 _usrAmount) external;

    function withdraw(uint256 _usrAmount) external;

    function withdrawAll() external;

    function previewDeposit(uint256 _usrAmount) external view returns (uint256 shares);

    function previewWithdraw(uint256 _usrAmount) external view returns (uint256 shares);
}