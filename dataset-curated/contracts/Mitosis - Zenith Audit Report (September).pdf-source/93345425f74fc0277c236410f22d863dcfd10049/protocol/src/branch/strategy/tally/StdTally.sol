// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Versioned } from '../../../lib/Versioned.sol';

/**
 * @title StdTally
 * @notice Tally is query helper to make easy to track balances
 */
abstract contract StdTally is Versioned {
  function totalBalance(bytes memory context) external view returns (uint256 totalBalance_) {
    return _totalBalance(context);
  }

  function pendingDepositBalance(bytes memory context) public view virtual returns (uint256 pendingDepositBalance_) {
    return _pendingDepositBalance(context);
  }

  function pendingWithdrawBalance(bytes memory context) public view virtual returns (uint256 pendingWithdrawBalance_) {
    return _pendingWithdrawBalance(context);
  }

  /**
   * @dev must implement this
   */
  function _totalBalance(bytes memory context) internal view virtual returns (uint256 totalBalance_);

  /**
   * @dev override this if the strategy is supporting async deposit
   */
  function _pendingDepositBalance(bytes memory) internal view virtual returns (uint256 pendingDepositBalance_) {
    return 0; // as default
  }

  /**
   * @dev override this if the strategy is supporting async withdraw
   */
  function _pendingWithdrawBalance(bytes memory) internal view virtual returns (uint256 pendingWithdrawBalance_) {
    return 0; // as default
  }
}
