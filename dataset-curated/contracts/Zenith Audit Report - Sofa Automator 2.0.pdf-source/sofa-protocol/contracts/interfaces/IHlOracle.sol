// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IHlOracle {
    function settlePrices(uint256, uint256) external view returns (uint256);
    function settle() external;
    function getHlPrices(uint256 term, uint256 expiry) external view returns (uint256[2] memory);
}
