// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import './actions/EnjoyoorsVaultDeposits.sol';
import './actions/EnjoyoorsVaultWithdrawals.sol';

/// @title Vault contract of Enjoyoors project
contract EnjoyoorsVault is EnjoyoorsVaultDeposits, EnjoyoorsVaultWithdrawals {
  /**
   * @param defaultAdmin Address which will be able to grant and revoke contract roles
   * @param _withdrawalApprover Address of contract used for verification of withdrawal requests in claiming process
   */
  constructor(
    address defaultAdmin,
    address _withdrawalApprover
  ) Access(defaultAdmin) EnjoyoorsVaultBase(_withdrawalApprover) {}

  /// @inheritdoc IEnjoyoorsVault
  function deposit(address token, uint256 amount) external {
    _deposit(token, amount);
  }

  /// @inheritdoc IEnjoyoorsVault
  function requestWithdrawal(address token, uint256 amount) external returns (uint256 requestId) {
    return _requestWithdrawal(token, amount);
  }

  /// @inheritdoc IEnjoyoorsVault
  function claimWithdrawal(
    uint256 requestId,
    bytes calldata approverData
  ) external returns (address token, uint256 amount) {
    return _claimWithdrawal(requestId, approverData);
  }
}
