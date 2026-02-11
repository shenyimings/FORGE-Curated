// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {TickLib} from "./TickLib.sol";
import {IUniV4} from "../interfaces/IUniV4.sol";

struct TickIteratorUp {
    IPoolManager manager;
    PoolId poolId;
    int24 tickSpacing;
    int24 currentTick;
    int24 endTick;
    uint256 currentWord;
}

struct TickIteratorDown {
    IPoolManager manager;
    PoolId poolId;
    int24 tickSpacing;
    int24 currentTick;
    int24 endTick;
    uint256 currentWord;
}

using TickIteratorLib for TickIteratorDown global;
using TickIteratorLib for TickIteratorUp global;

/// @author philogy <https://github.com/philogy>
library TickIteratorLib {
    using TickLib for int24;
    using TickLib for uint256;
    using IUniV4 for IPoolManager;

    error InvalidRange();
    error NoNext();

    // ============ Upward Iterator (Low to High) ============

    /// @notice Initialize an upward tick iterator
    /// @param manager The pool manager contract
    /// @param poolId The ID of the pool to iterate
    /// @param tickSpacing The tick spacing of the pool
    /// @param startTick The starting tick (exclusive)
    /// @param endTick The ending tick (inclusive)
    /// @return self The initialized iterator
    function initUp(
        IPoolManager manager,
        PoolId poolId,
        int24 tickSpacing,
        int24 startTick,
        int24 endTick
    ) internal view returns (TickIteratorUp memory self) {
        self.manager = manager;
        self.poolId = poolId;
        self.tickSpacing = tickSpacing;
        self.endTick = endTick;

        self.reset(startTick);
        return self;
    }

    function reset(TickIteratorUp memory self, int24 startTick) internal view {
        if (!(startTick <= self.endTick)) revert InvalidRange();
        self.currentTick = startTick;

        if (startTick == self.endTick) {
            self.currentTick = type(int24).max;
            return;
        }

        (int16 wordPos,) = TickLib.position(startTick.compress(self.tickSpacing));
        self.currentWord = self.manager.getPoolBitmapInfo(self.poolId, wordPos);

        _advanceToNextUp(self);
    }

    /// @notice Check if the iterator has more ticks
    /// @param self The iterator
    /// @return True if there are more ticks to iterate
    function hasNext(TickIteratorUp memory self) internal pure returns (bool) {
        return self.currentTick <= self.endTick;
    }

    function peekNext(TickIteratorUp memory self) internal pure returns (int24) {
        if (!hasNext(self)) revert NoNext();
        return self.currentTick;
    }

    /// @notice Get the next tick and advance the iterator
    /// @param self The iterator
    /// @return tick The next initialized tick
    function getNext(TickIteratorUp memory self) internal view returns (int24 tick) {
        if (!hasNext(self)) revert NoNext();
        tick = self.currentTick;
        _advanceToNextUp(self);
    }

    function _advanceToNextUp(TickIteratorUp memory self) private view {
        do {
            (int16 wordPos, uint8 bitPos) =
                TickLib.position(TickLib.compress(self.currentTick, self.tickSpacing) + 1);

            if (bitPos == 0) {
                self.currentWord = self.manager.getPoolBitmapInfo(self.poolId, wordPos);
            }

            bool initialized;
            (initialized, bitPos) = self.currentWord.nextBitPosGte(bitPos);
            self.currentTick = TickLib.toTick(wordPos, bitPos, self.tickSpacing);
            if (initialized) break;
        } while (self.currentTick <= self.endTick);
    }

    // ============ Downward Iterator (High to Low) ============

    /// @notice Initialize a downward tick iterator
    /// @param manager The pool manager contract
    /// @param poolId The ID of the pool to iterate
    /// @param tickSpacing The tick spacing of the pool
    /// @param startTick The starting tick (exclusive, should be higher)
    /// @param endTick The ending tick (exclusive, should be lower)
    /// @return self The initialized iterator
    function initDown(
        IPoolManager manager,
        PoolId poolId,
        int24 tickSpacing,
        int24 startTick,
        int24 endTick
    ) internal view returns (TickIteratorDown memory self) {
        self.manager = manager;
        self.poolId = poolId;
        self.tickSpacing = tickSpacing;
        self.endTick = endTick;

        self.reset(startTick);
        return self;
    }

    function reset(TickIteratorDown memory self, int24 startTick) internal view {
        if (!(self.endTick <= startTick)) revert InvalidRange();
        self.currentTick = startTick;

        if (startTick == self.endTick) return;

        (int16 wordPos,) = TickLib.position(startTick.compress(self.tickSpacing));
        self.currentWord = self.manager.getPoolBitmapInfo(self.poolId, wordPos);

        _advanceToNextDown(self);
    }

    /// @notice Check if the iterator has more ticks
    /// @param self The iterator
    /// @return True if there are more ticks to iterate
    function hasNext(TickIteratorDown memory self) internal pure returns (bool) {
        return self.currentTick > self.endTick;
    }

    /// @notice Get the next tick and advance the iterator
    /// @param self The iterator
    /// @return tick The next initialized tick
    function getNext(TickIteratorDown memory self) internal view returns (int24 tick) {
        if (!hasNext(self)) revert NoNext();
        tick = self.currentTick;
        _advanceToNextDown(self);
    }

    function _advanceToNextDown(TickIteratorDown memory self) private view {
        do {
            (int16 wordPos, uint8 bitPos) =
                TickLib.position((self.currentTick - 1).compress(self.tickSpacing));

            if (bitPos == 255) {
                self.currentWord = self.manager.getPoolBitmapInfo(self.poolId, wordPos);
            }

            bool initialized;
            (initialized, bitPos) = self.currentWord.nextBitPosLte(bitPos);
            self.currentTick = TickLib.toTick(wordPos, bitPos, self.tickSpacing);
            if (initialized) break;
        } while (self.endTick < self.currentTick);
    }
}
