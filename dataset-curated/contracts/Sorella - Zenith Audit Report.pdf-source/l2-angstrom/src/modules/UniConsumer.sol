// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "../interfaces/IUniV4.sol";

/// @author philogy <https://github.com/philogy>
abstract contract UniConsumer {
    error NotUniswap();

    IPoolManager internal immutable UNI_V4;

    constructor(IPoolManager uniV4) {
        UNI_V4 = uniV4;
    }

    function _onlyUniV4() internal view {
        if (!(msg.sender == address(UNI_V4))) revert NotUniswap();
    }
}
