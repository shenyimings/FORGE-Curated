// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracle {
    function name() external view returns (string memory);

    function peek(uint256 baseAmount) external view returns (uint256 answer);
}
