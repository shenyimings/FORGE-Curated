// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';

import { StdError } from './StdError.sol';

library LibCheckpoint {
  using SafeCast for uint256;

  struct TWABCheckpoint {
    uint256 twab;
    uint208 amount;
    uint48 lastUpdate;
  }

  struct TraceTWAB {
    TWABCheckpoint[] checkpoints;
  }

  function add(uint256 x, uint256 y) internal pure returns (uint256) {
    unchecked {
      return x + y;
    }
  }

  function sub(uint256 x, uint256 y) internal pure returns (uint256) {
    unchecked {
      return x - y;
    }
  }

  function len(TraceTWAB storage self) internal view returns (uint256) {
    return self.checkpoints.length;
  }

  function last(TraceTWAB storage self) internal view returns (TWABCheckpoint storage) {
    return self.checkpoints[len(self) - 1];
  }

  function push(
    TraceTWAB storage self,
    uint256 amount,
    uint48 now_,
    function (uint256, uint256) returns (uint256) nextAmountFunc
  ) internal {
    if (self.checkpoints.length == 0) {
      self.checkpoints.push(TWABCheckpoint({ twab: 0, amount: amount.toUint208(), lastUpdate: now_ }));
    } else {
      TWABCheckpoint memory last_ = last(self);

      self.checkpoints.push(
        TWABCheckpoint({
          // we assume `now` is always greater than `last_.lastUpdate`
          twab: last_.twab + (last_.amount * sub(now_, last_.lastUpdate)),
          amount: nextAmountFunc(last_.amount, amount).toUint208(),
          lastUpdate: now_
        })
      );
    }
  }

  /**
   * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
   * there is none.
   */
  function lowerLookup(TraceTWAB storage self, uint48 key) internal view returns (TWABCheckpoint memory) {
    uint256 len_ = len(self);
    uint256 pos = _lowerBinaryLookup(self, key, 0, len_);
    if (pos == len_) {
      TWABCheckpoint memory empty;
      return empty;
    }
    return _unsafeAccess(self.checkpoints, pos);
  }

  /**
   * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
   * if there is none.
   */
  function upperLookup(TraceTWAB storage self, uint48 key) internal view returns (TWABCheckpoint memory) {
    uint256 len_ = len(self);
    uint256 pos = _upperBinaryLookup(self, key, 0, len_);
    if (pos == 0) {
      TWABCheckpoint memory empty;
      return empty;
    }
    return _unsafeAccess(self.checkpoints, pos - 1);
  }

  /**
   * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
   * if there is none.
   *
   * NOTE: This is a variant of {upperLookup} that is optimised to find "recent" checkpoint (checkpoints with high
   * keys).
   */
  function upperLookupRecent(TraceTWAB storage self, uint48 key) internal view returns (TWABCheckpoint memory) {
    uint256 len_ = len(self);

    uint256 low = 0;
    uint256 high = len_;

    if (len_ > 5) {
      uint256 mid = len_ - Math.sqrt(len_);
      if (key < _unsafeAccess(self.checkpoints, mid).lastUpdate) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }

    uint256 pos = _upperBinaryLookup(self, key, low, high);
    if (pos == 0) {
      TWABCheckpoint memory empty;
      return empty;
    }

    return _unsafeAccess(self.checkpoints, pos - 1);
  }

  /**
   * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or `high`
   * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
   * `high`.
   *
   * WARNING: `high` should not be greater than the array's length.
   */
  function _lowerBinaryLookup(TraceTWAB storage self, uint48 key, uint256 low, uint256 high)
    private
    view
    returns (uint256)
  {
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (_unsafeAccess(self.checkpoints, mid).lastUpdate < key) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return high;
  }

  /**
   * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or `high`
   * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
   * `high`.
   *
   * WARNING: `high` should not be greater than the array's length.
   */
  function _upperBinaryLookup(TraceTWAB storage self, uint48 key, uint256 low, uint256 high)
    private
    view
    returns (uint256)
  {
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (_unsafeAccess(self.checkpoints, mid).lastUpdate > key) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return high;
  }

  /**
   * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
   */
  function _unsafeAccess(TWABCheckpoint[] storage self, uint256 pos)
    private
    pure
    returns (TWABCheckpoint storage result)
  {
    assembly {
      // Get the array's storage slot
      mstore(0, self.slot)
      // Multiply position by 2 (since each element takes 2 storage slots)
      let slotOffset := shl(1, pos)
      // Add the offset to the base storage location
      result.slot := add(keccak256(0, 0x20), slotOffset)
    }
  }
}
