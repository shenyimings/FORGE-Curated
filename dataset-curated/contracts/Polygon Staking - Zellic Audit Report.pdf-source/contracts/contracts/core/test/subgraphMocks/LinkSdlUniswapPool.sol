// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockLinkSdlUniswapPool {
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
            sqrtPriceX96: 539950026751222674039685537688,
            tick: 38384,
            observationIndex: 0,
            observationCardinality: 1,
            observationCardinalityNext: 1,
            feeProtocol: 0,
            unlocked: true
        });
    }
}
