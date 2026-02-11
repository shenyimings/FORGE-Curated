// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockLinkSdlSushiPool {
    struct Reserves {
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
    }

    Reserves private _reserves;

    constructor() {
        _reserves = Reserves({
            reserve0: 50280390552967262265,
            reserve1: 2263776855667093842130,
            blockTimestampLast: 1724692727
        });
    }

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        return (_reserves.reserve0, _reserves.reserve1, _reserves.blockTimestampLast);
    }
}
