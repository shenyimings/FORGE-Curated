// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IStRCH {
    function balanceOf(address account) external view returns (uint256);
    function mint(uint256 amount) external;
    function withdraw(address to, uint256 amount) external;
}
