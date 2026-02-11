// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarginState} from "./MarginState.sol";
import {Reserves} from "./Reserves.sol";

struct PoolState {
    MarginState marginState;
    uint128 totalSupply;
    uint32 lastUpdated;
    uint24 lpFee;
    uint24 marginFee;
    uint24 protocolFee;
    uint256 borrow0CumulativeLast;
    uint256 borrow1CumulativeLast;
    uint256 deposit0CumulativeLast;
    uint256 deposit1CumulativeLast;
    Reserves realReserves;
    Reserves mirrorReserves;
    Reserves pairReserves;
    Reserves truncatedReserves;
    Reserves lendReserves;
    Reserves interestReserves;
}
