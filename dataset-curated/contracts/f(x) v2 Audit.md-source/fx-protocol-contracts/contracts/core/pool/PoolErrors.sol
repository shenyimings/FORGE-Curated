// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

abstract contract PoolErrors {
  /**********
   * Errors *
   **********/
  
  /// @dev Thrown when the given address is zero.
  error ErrorZeroAddress();

  /// @dev Thrown when the given value exceeds maximum value.
  error ErrorValueTooLarge();
  
  /// @dev Thrown when the caller is not pool manager.
  error ErrorCallerNotPoolManager();
  
  /// @dev Thrown when the debt amount is too small.
  error ErrorDebtTooSmall();

  /// @dev Thrown when the collateral amount is too small.
  error ErrorCollateralTooSmall();
  
  /// @dev Thrown when both collateral amount and debt amount are zero.
  error ErrorNoSupplyAndNoBorrow();
  
  /// @dev Thrown when borrow is paused.
  error ErrorBorrowPaused();

  /// @dev Thrown when redeem is paused.
  error ErrorRedeemPaused();
  
  /// @dev Thrown when the caller is not position owner during withdraw or borrow.
  error ErrorNotPositionOwner();
  
  /// @dev Thrown when withdraw more than supplied.
  error ErrorWithdrawExceedSupply();
  
  /// @dev Thrown when the debt ratio is too small.
  error ErrorDebtRatioTooSmall();

  /// @dev Thrown when the debt ratio is too large.
  error ErrorDebtRatioTooLarge();
  
  /// @dev Thrown when pool is under collateral.
  error ErrorPoolUnderCollateral();
  
  /// @dev Thrown when the current debt ratio <= rebalance debt ratio.
  error ErrorRebalanceDebtRatioNotReached();

  /// @dev Thrown when the current debt ratio > liquidate debt ratio.
  error ErrorPositionInLiquidationMode();

  error ErrorRebalanceOnLiquidatableTick();

  error ErrorRebalanceOnLiquidatablePosition();

  error ErrorInsufficientCollateralToLiquidate();

  error ErrorOverflow();

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to check value not too large.
  /// @param value The value to check.
  /// @param upperBound The upper bound for the given value.
  function _checkValueTooLarge(uint256 value, uint256 upperBound) internal pure {
    if (value > upperBound) revert ErrorValueTooLarge();
  }

  function _checkAddressNotZero(address value) internal pure {
    if (value == address(0)) revert ErrorZeroAddress();
  }
}
