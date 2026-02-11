// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CumulativePrice} from "src/amm/base/CumulativePrice.sol";

/**
 * @title Simple Price Oracle
 * @notice This is an example implementation of price oracle using ALTBC and URQTBC Pools
 * @dev During deployment the pool address is set in the constructor
 */
contract SimplePriceOracle {
    uint public constant PERIOD = 1000; // minimum update interval in seconds
    address public pool;

    uint public priceCumulativeLast;
    uint public blockTimestampLast;
    uint public priceAverage;

    constructor(address _pool) {
        pool = _pool;
    }

    function update() external {
        uint cumulativePrice = CumulativePrice(pool).cumulativePrice();
        uint blockTimestamp = CumulativePrice(pool).lastBlockTimestamp();
        uint elapsedTime = blockTimestamp - blockTimestampLast;

        // ensure that at least one full period has passed since the last update
        require(elapsedTime >= PERIOD, 'Minimum PERIOD required');

        priceAverage = (cumulativePrice - priceCumulativeLast) / elapsedTime;
        blockTimestampLast = blockTimestamp;
        priceCumulativeLast = cumulativePrice;
    }

}