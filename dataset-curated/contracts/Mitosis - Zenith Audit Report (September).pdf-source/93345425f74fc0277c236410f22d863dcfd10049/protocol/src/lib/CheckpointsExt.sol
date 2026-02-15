// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { Checkpoints } from '@oz/utils/structs/Checkpoints.sol';

import { StdError } from './StdError.sol';

/// @title CheckpointsExt
/// @notice Extension of the OpenZeppelin Checkpoints library.
/// @dev We've made a PR to expose these functions, but not sure if it will be merged.
/// (https://github.com/OpenZeppelin/openzeppelin-contracts/pull/5609)
library CheckpointsExt {
  using SafeCast for uint256;

  /**
   * @dev Return the value of the checkpoint at `index`.
   */
  function valueAt(Checkpoints.Trace208 storage self, uint32 pos) internal view returns (uint208) {
    return self._checkpoints[pos]._value;
  }

  /**
   * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or `high`
   * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
   * `high`.
   *
   * WARNING: `high` should not be greater than the array's length.
   */
  function upperBinaryLookup(Checkpoints.Trace208 storage self, uint48 key, uint256 low, uint256 high)
    internal
    view
    returns (uint256)
  {
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (_unsafeAccess(self._checkpoints, mid)._key > key) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return high;
  }

  /**
   * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or `high`
   * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
   * `high`.
   *
   * WARNING: `high` should not be greater than the array's length.
   */
  function lowerBinaryLookup(Checkpoints.Trace208 storage self, uint48 key, uint256 low, uint256 high)
    internal
    view
    returns (uint256)
  {
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (_unsafeAccess(self._checkpoints, mid)._key < key) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return high;
  }

  /**
   * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
   */
  function _unsafeAccess(Checkpoints.Checkpoint208[] storage self, uint256 pos)
    private
    pure
    returns (Checkpoints.Checkpoint208 storage result)
  {
    assembly {
      mstore(0, self.slot)
      result.slot := add(keccak256(0, 0x20), pos)
    }
  }
}
