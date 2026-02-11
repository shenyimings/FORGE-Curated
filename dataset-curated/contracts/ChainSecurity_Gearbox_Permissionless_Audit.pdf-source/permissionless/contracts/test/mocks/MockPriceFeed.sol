// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    uint256 private _lastUpdateTime;
    int256 private _price;
    bytes32 private constant _CONTRACT_TYPE = "MOCK_PRICE_FEED";
    uint256 private constant _VERSION = 1;

    constructor() {
        _lastUpdateTime = block.timestamp;
        _price = 1e18; // Default price of 1
    }

    function lastUpdateTime() external view returns (uint256) {
        return _lastUpdateTime;
    }

    function version() external pure returns (uint256) {
        return _VERSION;
    }

    function contractType() external pure returns (bytes32) {
        return _CONTRACT_TYPE;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _price, _lastUpdateTime, _lastUpdateTime, 0);
    }

    // Test helper functions
    function setLastUpdateTime(uint256 timestamp) external {
        _lastUpdateTime = timestamp;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function decimals() external pure returns (uint8) {
        return 8; // Standard 8 decimals for USD oracles
    }

    function description() external pure returns (string memory) {
        return "Mock Price Feed";
    }

    function skipPriceCheck() external pure returns (bool) {
        return false;
    }
}
