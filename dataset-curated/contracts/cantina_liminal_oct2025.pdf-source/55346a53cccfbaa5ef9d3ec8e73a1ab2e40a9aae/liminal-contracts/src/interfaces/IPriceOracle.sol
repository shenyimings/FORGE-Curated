// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title IPriceOracle
 * @notice Interface for price oracle
 */
interface IPriceOracle {
    function getPrice(address asset) external view returns (uint256);
    function getPriceInUSD(address asset) external view returns (uint256);
    function convertAmount(address fromAsset, address toAsset, uint256 amount) external view returns (uint256);
}
