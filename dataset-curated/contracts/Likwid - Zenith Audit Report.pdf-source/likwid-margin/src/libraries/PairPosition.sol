// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.0;

import {BalanceDelta} from "../types/BalanceDelta.sol";
import {CustomRevert} from "./CustomRevert.sol";
import {PositionLibrary} from "./PositionLibrary.sol";
import {LiquidityMath} from "./LiquidityMath.sol";

/// @title PairPosition
/// @notice A library for managing liquidity positions in a pair.
/// @dev Positions represent an owner's liquidity contribution.
library PairPosition {
    using CustomRevert for bytes4;
    using PositionLibrary for address;

    error CannotUpdateEmptyPosition();

    /// @dev Represents the state of a liquidity position.
    struct State {
        // The amount of liquidity in the position.
        uint128 liquidity;
        // The total investment value, used for tracking returns.
        uint256 totalInvestment;
    }

    /// @notice Retrieves a position's state from storage.
    /// @param self The mapping of position keys to position states.
    /// @param owner The owner of the position.
    /// @param salt A unique salt for the position.
    /// @return position A storage pointer to the position's state.
    function get(mapping(bytes32 => State) storage self, address owner, bytes32 salt)
        internal
        view
        returns (State storage position)
    {
        bytes32 positionKey = owner.calculatePositionKey(salt);
        position = self[positionKey];
    }

    /// @notice Updates a position's state with new liquidity and investment amounts.
    /// @param self A storage pointer to the position's state to update.
    /// @param liquidityDelta The change in liquidity.
    /// @param delta The change in the balance of tokens.
    /// @return The updated total investment value.
    function update(State storage self, int128 liquidityDelta, BalanceDelta delta) internal returns (uint256) {
        // If there's no change in liquidity and the position is empty, revert.
        // This prevents creating empty positions or "poking" them without effect.
        if (liquidityDelta == 0 && self.liquidity == 0) {
            CannotUpdateEmptyPosition.selector.revertWith();
        }

        if (liquidityDelta != 0) {
            self.liquidity = LiquidityMath.addDelta(self.liquidity, liquidityDelta);
        }

        // Update the total investment and store it.
        self.totalInvestment = LiquidityMath.addInvestment(self.totalInvestment, delta.amount0(), delta.amount1());
        return self.totalInvestment;
    }
}
