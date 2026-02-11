// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.26;

import './IEnjoyoorsWithdrawalApprover.sol';

/**
 * @title Interface of vaults used in Enjoyoors project
 * @notice Includes user-related action calls and view methods
 */
interface IEnjoyoorsVault {
  /// @notice Struct with withdrawal request data
  struct WithdrawalRequest {
    /// @dev Amount of `token` that will be claimed after request finalization
    uint256 amount;
    /// @dev Address, receiving `token` in `claimWithdrawal`
    address user;
    /// @dev Token received in `claimWithdrawal`
    address token;
    /// @dev Timestamp when this request was submitted
    uint184 timestamp;
    /// @dev Shows if this request is already claimed
    bool claimed;
  }

  /**
   * @notice Method to deposit given `amount` of `token` to vault
   * @dev Reverts if deposits are paused
   * @param token Address of a vault-listed token
   * @param amount Amount of `token` to deposit. Must be less than `supplyTillLimit`
   */
  function deposit(address token, uint256 amount) external;

  /**
   * @notice Method to request withdrawal given `amount` of `token` to vault
   * @dev Reverts if amount is greater than `userSupply`. Reverts if withdrawal requests are paused
   * @param token Address of vault-listed token
   * @param amount Amount of `token` to withdraw
   * @return requestId Id of this request if successful
   */
  function requestWithdrawal(address token, uint256 amount) external returns (uint256 requestId);

  /**
   * @notice Method to claim withdrawals
   * @dev Withdrawal request must be approved by `withdrawalApprover`. Reverts if withdrawal claiming is paused
   * @param requestId Id of a request to claim
   * @param approverData Data used by`withdrawalApprover` in a verification process
   * @return token Claimed token address
   * @return amount Claimed `token` amount
   */
  function claimWithdrawal(
    uint256 requestId,
    bytes calldata approverData
  ) external returns (address token, uint256 amount);

  /**
   * @return Total `token` supply in vault
   * @dev Decreased in `requestWithdrawal` and immutable in `claimWithdrawal`
   * @param token Token which supply is returned
   */
  function totalSupply(address token) external view returns (uint256);

  /**
   * @return Given `token` supply of `user` in vault
   * @dev Decreased in`requestWithdrawal` and immutable in `claimWithdrawal`
   * @param token Token which supply is returned
   * @param user User whose `token` supply is returned
   */
  function userSupply(address token, address user) external view returns (uint256);

  /**
   * @return Allowed deposit amount of given `token` before reaching maximum capitalization
   * @dev Decreased in `claimWithdrawal` and immutable in `requestWithdrawal`
   * @param token Token which `supplyTillLimit` value is returned
   */
  function supplyTillLimit(address token) external view returns (uint256);

  /**
   * @return If given `token` can be deposited to vault
   * @param token Token to search in whitelist
   */
  function isWhitelistedToken(address token) external view returns (bool);

  /// @return Contract which is called in `claimWithdrawal` for verification
  function withdrawalApprover() external view returns (IEnjoyoorsWithdrawalApprover);

  /// @return Id of the most recent withdrawal request
  function lastRequestId() external view returns (uint256);

  /**
   * @return `WithdrawalRequest` with given `requestId`
   * @dev Returns default value for `requestId` > `lastRequestId`
   * @param requestId Id of withdrawal request
   */
  function getWithdrawalRequestById(uint256 requestId) external view returns (WithdrawalRequest memory);
}
