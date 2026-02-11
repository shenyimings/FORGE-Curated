// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface ISpotOracle {
    function settlePrices(uint256) external view returns (uint256);
    function settle() external;
}
