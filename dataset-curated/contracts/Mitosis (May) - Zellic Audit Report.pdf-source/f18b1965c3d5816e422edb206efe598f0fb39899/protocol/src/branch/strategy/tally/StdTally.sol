// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// TODO(ray):
//      How to query cases like Uniswap v3 (when there are multiple positions)
//      How to manage claimId, etc., when a redeem period exists.
/**
 * @title StdTally
 * @notice Tally is query helper to make easy to track balances
 */
abstract contract StdTally {
  function protocolAddress() external view virtual returns (address);

  function totalBalance(bytes memory context) external view returns (uint256 totalBalance_) {
    return _totalBalance(context);
  }

  function withdrawableBalance(bytes memory context) external view returns (uint256 withdrawableBalance_) {
    return _withdrawableBalance(context);
  }

  function pendingDepositBalance(bytes memory context) public view virtual returns (uint256 pendingDepositBalance_) {
    return _pendingDepositBalance(context);
  }

  function pendingWithdrawBalance(bytes memory context) public view virtual returns (uint256 pendingWithdrawBalance_) {
    return _pendingWithdrawBalance(context);
  }

  function previewDeposit(uint256 amount, bytes memory context) external view returns (uint256 deposited) {
    return _previewDeposit(amount, context);
  }

  function previewWithdraw(uint256 amount, bytes memory context) external view returns (uint256 withdrawn) {
    return _previewWithdraw(amount, context);
  }

  /**
   * @dev must override this if the strategy is supporting async deposit
   */
  function _isDepositAsync() internal pure virtual returns (bool) {
    return false; // as default
  }

  /**
   * @dev must override this if the strategy is supporting async withdraw
   */
  function _isWithdrawAsync() internal pure virtual returns (bool) {
    return false; // as default
  }

  /**
   * @dev must implement this
   */
  function _totalBalance(bytes memory context) internal view virtual returns (uint256 totalBalance_);

  /**
   * @dev override this if the strategy is supporting async withdraw
   */
  function _withdrawableBalance(bytes memory context) internal view virtual returns (uint256 withdrawableBalance_) {
    return _totalBalance(context); // as default
  }

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

  function _previewDeposit(uint256 amount, bytes memory) internal view virtual returns (uint256) {
    return _isDepositAsync() ? 0 : amount;
  }

  function _previewWithdraw(uint256 amount, bytes memory) internal view virtual returns (uint256) {
    return _isWithdrawAsync() ? 0 : amount;
  }
}
