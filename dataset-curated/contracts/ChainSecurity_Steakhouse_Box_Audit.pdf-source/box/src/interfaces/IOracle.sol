// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice Oracle interface to get a token price with 36 decimals of precision
interface IOracle {
    function price() external view returns (uint256);
}
