// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { BitMath } from "./BitMath.sol";

library TickBitmap {
  function position(int16 tick) private pure returns (int8 wordPos, uint8 bitPos) {
    assembly {
      wordPos := shr(8, tick)
      bitPos := and(tick, 255)
    }
  }

  function flipTick(mapping(int8 => uint256) storage self, int16 tick) internal {
    (int8 wordPos, uint8 bitPos) = position(tick);
    uint256 mask = 1 << bitPos;
    self[wordPos] ^= mask;
  }

  function isBitSet(mapping(int8 => uint256) storage self, int16 tick) internal view returns (bool) {
    (int8 wordPos, uint8 bitPos) = position(tick);
    uint256 mask = 1 << bitPos;
    return (self[wordPos] & mask) > 0;
  }

  /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is
  /// to the left (less than or equal to).
  function nextDebtPositionWithinOneWord(
    mapping(int8 => uint256) storage self,
    int16 tick
  ) internal view returns (int16 next, bool hasDebt) {
    unchecked {
      // start from the word of the next tick, since the current tick state doesn't matter
      (int8 wordPos, uint8 bitPos) = position(tick);
      // all the 1s at or to the right of the current bitPos
      uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
      uint256 masked = self[wordPos] & mask;

      // if there are no initialized ticks to the left of the current tick, return leftmost in the word
      hasDebt = masked != 0;
      // overflow/underflow is possible, but prevented externally by limiting tick
      next = hasDebt
        ? (tick - int16(uint16(bitPos - BitMath.mostSignificantBit(masked))))
        : (tick - int16(uint16(bitPos)));
    }
  }
}
