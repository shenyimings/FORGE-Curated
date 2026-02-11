// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9;

interface IWETH9 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function approve(address guy, uint256 wad) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function allowance(
        address account,
        address spender
    ) external view returns (uint256);
}
