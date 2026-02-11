// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IWhitelist {
    function checkWhitelist(address from, address to, uint256 amount) external;
}
