// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum MarginActions {
    MARGIN,
    REPAY,
    CLOSE,
    MODIFY,
    LIQUIDATE_BURN,
    LIQUIDATE_CALL
}
