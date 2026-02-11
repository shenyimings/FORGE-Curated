// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.26;

/// @title Interface of a contract which is called in `IEnjoyoorsVault.claimWithdrawal` for verification
interface IEnjoyoorsWithdrawalApprover {
  /**
   * @notice Revert reason if there was an attempt to claim not approved withdrawal
   * @param requestId Id of not approved withdrawal request which caused revert
   */
  error NotApproved(uint256 requestId);

  /**
   * @notice Method for withdrawal verification in `IEnjoyoorsVault.claimWithdrawal`
   * @dev Reverts with `NotApproved` if withdrawal is not yet approved
   * @param requestId Id of withdrawal request to be verified
   * @param approverData Extra data used in verification process
   */
  function verifyWithdrawalApproved(uint256 requestId, bytes calldata approverData) external view;
}
