// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockMetisEthUniswapPool {
    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    Slot0 public slot0;

    constructor() {
        slot0 = Slot0({
            sqrtPriceX96: 9016690058901672876185056108,
            tick: -43030,
            observationIndex: 52,
            observationCardinality: 80,
            observationCardinalityNext: 80,
            feeProtocol: 0,
            unlocked: true
        });
    }
}
