// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IChainlinkAggregatorLike } from "../../src/interfaces/IChainlinkAggregatorLike.sol";

contract MockPriceFeed is IChainlinkAggregatorLike {
    int256 public price;
    uint256 public updatedAt;
    uint8 public decimals;

    constructor(int256 initialPrice, uint8 priceDecimals) {
        price = initialPrice;
        decimals = priceDecimals;
    }

    function setPrice(int256 _newPrice) external {
        setPrice(_newPrice, 0);
    }

    function setPrice(int256 _newPrice, uint256 _updatedAt) public {
        price = _newPrice;
        updatedAt = _updatedAt;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, updatedAt == 0 ? block.timestamp : updatedAt, 0);
    }
}
