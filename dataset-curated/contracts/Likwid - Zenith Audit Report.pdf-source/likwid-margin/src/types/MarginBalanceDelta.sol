// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarginActions} from "./MarginActions.sol";
import {BalanceDelta} from "./BalanceDelta.sol";

struct MarginBalanceDelta {
    MarginActions action;
    bool marginForOne;
    uint128 marginTotal;
    uint24 marginFee;
    uint256 swapFeeAmount;
    BalanceDelta marginDelta;
    BalanceDelta realDelta;
    BalanceDelta mirrorDelta;
    BalanceDelta pairDelta;
    BalanceDelta lendDelta;
    uint256 debtDepositCumulativeLast;
}
