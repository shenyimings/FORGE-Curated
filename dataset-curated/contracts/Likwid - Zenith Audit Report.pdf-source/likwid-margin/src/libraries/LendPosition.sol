// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.0;

import {Math} from "./Math.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {CustomRevert} from "./CustomRevert.sol";
import {PositionLibrary} from "./PositionLibrary.sol";
import {SafeCast} from "./SafeCast.sol";

/// @title LendPosition
/// @notice Positions represent an owner address' lend tokens
library LendPosition {
    using CustomRevert for bytes4;
    using PositionLibrary for address;
    using SafeCast for *;

    error CannotUpdateEmptyPosition();

    error WithdrawOverflow();

    struct State {
        uint128 lendAmount;
        uint256 depositCumulativeLast;
    }

    function get(mapping(bytes32 => State) storage self, address owner, bool lendForOne, bytes32 salt)
        internal
        view
        returns (State storage position)
    {
        bytes32 positionKey = owner.calculatePositionKey(lendForOne, salt);
        position = self[positionKey];
    }

    function update(State storage self, bool lendForOne, uint256 depositCumulativeLast, BalanceDelta delta)
        internal
        returns (uint256)
    {
        int128 amount;
        if (lendForOne) {
            amount = delta.amount1();
        } else {
            amount = delta.amount0();
        }
        if ((delta == BalanceDeltaLibrary.ZERO_DELTA && self.lendAmount == 0) || amount == 0) {
            CannotUpdateEmptyPosition.selector.revertWith();
        }

        uint256 lendAmount;
        if (self.depositCumulativeLast != 0) {
            lendAmount = Math.mulDiv(self.lendAmount, depositCumulativeLast, self.depositCumulativeLast);
        }

        if (amount < 0) {
            // deposit
            lendAmount += uint128(-amount);
        } else {
            // withdraw
            if (uint128(amount) > lendAmount) {
                WithdrawOverflow.selector.revertWith();
            }
            lendAmount -= uint128(amount);
        }
        self.lendAmount = lendAmount.toUint128();
        self.depositCumulativeLast = depositCumulativeLast;

        return self.lendAmount;
    }
}
