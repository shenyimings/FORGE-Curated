// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IReservePool {
  /// @notice Emitted when the market request bonus.
  /// @param token The address of the token requested.
  /// @param receiver The address of token receiver.
  /// @param bonus The amount of bonus token.
  event RequestBonus(address indexed token, address indexed receiver, uint256 bonus);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the balance of token in this contract.
  function getBalance(address token) external view returns (uint256);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Request bonus token from Reserve Pool.
  /// @param token The address of token to request.
  /// @param receiver The address recipient for the bonus token.
  /// @param bonus The amount of bonus token to send.
  function requestBonus(address token, address receiver, uint256 bonus) external;

  /// @notice Withdraw dust assets in this contract.
  /// @param token The address of token to withdraw.
  /// @param amount The amount of token to withdraw.
  /// @param recipient The address of token receiver.
  function withdrawFund(address token, uint256 amount, address recipient) external;
}
