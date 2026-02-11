// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IAss {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}