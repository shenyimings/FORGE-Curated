// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract MockOracle {
    mapping(address => uint256) private prices; // 18 decimals
    mapping(address => uint256) private lastUpdate;
    uint256 public constant PRICE_PRECISION = 1e18;

    event PriceUpdated(address asset, uint256 price);

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
        lastUpdate[asset] = block.timestamp;
        emit PriceUpdated(asset, price);
    }

    function getPrice(address asset) external view returns (uint256, uint256) {
        require(prices[asset] > 0, "Price not set");
        /// @dev lastUpdate is not used in the mock oracle
        return (prices[asset], block.timestamp);
    }

    function simulatePriceChange(address asset, int256 percentChange) external {
        require(prices[asset] > 0, "Price not set");
        if (percentChange > 0) {
            prices[asset] = (prices[asset] * uint256(100 + percentChange)) / 100;
        } else {
            prices[asset] = (prices[asset] * uint256(100 - (-percentChange))) / 100;
        }
        lastUpdate[asset] = block.timestamp;
        emit PriceUpdated(asset, prices[asset]);
    }
}
