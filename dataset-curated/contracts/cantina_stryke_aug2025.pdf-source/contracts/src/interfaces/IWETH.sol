// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
