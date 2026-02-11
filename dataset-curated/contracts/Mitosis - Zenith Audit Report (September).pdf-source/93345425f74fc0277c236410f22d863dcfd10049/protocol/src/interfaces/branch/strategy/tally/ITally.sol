// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface ITally {
  function totalBalance(bytes memory context) external view returns (uint256 totalBalance_);

  function withdrawableBalance(bytes memory context) external view returns (uint256 withdrawableBalance_);

  function pendingDepositBalance(bytes memory context) external view returns (uint256 pendingDepositBalance_);

  function pendingWithdrawBalance(bytes memory context) external view returns (uint256 pendingWithdrawBalance_);
}
