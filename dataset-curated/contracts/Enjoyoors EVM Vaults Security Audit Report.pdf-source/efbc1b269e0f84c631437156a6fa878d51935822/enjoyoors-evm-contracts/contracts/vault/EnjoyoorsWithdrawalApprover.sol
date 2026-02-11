// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import '@openzeppelin/contracts/access/AccessControl.sol';

import '../interfaces/IEnjoyoorsVault.sol';
import '../interfaces/IEnjoyoorsWithdrawalApprover.sol';
import '../libraries/Asserts.sol';

/// @title Contract for withdrawals approvals and verifications
contract EnjoyoorsWithdrawalApprover is IEnjoyoorsWithdrawalApprover, AccessControl {
  /// @notice Hash of role with changing contract params rights
  bytes32 public constant SETUP_ROLE = keccak256('SETUP_ROLE');

  /**
   * @notice Emitted in `changeWithdrawalPeriod` call
   * @param _old `withdrawalPeriodSeconds` value before the call
   * @param _new `withdrawalPeriodSeconds` value after the call
   */
  event WithdrawalPeriodChanged(uint256 _old, uint256 _new);

  /// @notice Revert reason if an attempt to set `withdrawalPeriodSeconds` to current value occurs
  error SameWithdrawalPeriod();

  /// @notice Minimal amount of time that should pass between submitting and claiming withdrawal requests
  uint256 public withdrawalPeriodSeconds;

  /**
   * @notice Sets `withdrawalPeriodSeconds` and grants `DEFAULT_ADMIN_ROLE` to deployer
   * @param _withdrawalPeriodSeconds Value for `withdrawalPeriodSeconds` storage
   */
  constructor(uint256 _withdrawalPeriodSeconds) {
    withdrawalPeriodSeconds = _withdrawalPeriodSeconds;
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /**
   * @inheritdoc IEnjoyoorsWithdrawalApprover
   * @dev `approverData` param is not used in this implementation
   */
  function canClaimWithdrawal(uint256 requestId, bytes calldata) external view {
    if (!_canClaimWithdrawal(msg.sender, requestId)) revert NotApproved(requestId);
  }

  /**
   * @return If request with `requestId` in `enjoyoorsVault` can be claimed right now
   * @param enjoyoorsVault Address of Enjoyoors project vault to get withdrawal request from
   * @param requestId Id of request
   */
  function vaultWithdrawalClaimable(
    address enjoyoorsVault,
    uint256 requestId,
    bytes calldata
  ) external view returns (bool) {
    return _canClaimWithdrawal(enjoyoorsVault, requestId);
  }

  /**
   * @notice Requires `SETUP_ROLE` rights. Changes `withdrawalPeriodSeconds` storage value
   * @param newWithdrawalPeriod New value for `withdrawalPeriodSeconds` storage
   */
  function changeWithdrawalPeriod(uint256 newWithdrawalPeriod) external onlyRole(SETUP_ROLE) {
    uint256 oldWithdrawalPeriod = withdrawalPeriodSeconds;
    if (oldWithdrawalPeriod == newWithdrawalPeriod) revert SameWithdrawalPeriod();

    withdrawalPeriodSeconds = newWithdrawalPeriod;
    emit WithdrawalPeriodChanged(oldWithdrawalPeriod, newWithdrawalPeriod);
  }

  /**
   * @notice Internal method for withdrawal requests verification
   * @dev Checks that request exists (its timestamp is not 0) and required time has passed since request submission
   * @param enjoyoorsVault Address of Enjoyoors project vault to get withdrawal request from
   * @param requestId Id of request
   * @return If request with `requestId` in `enjoyoorsVault` can be claimed right now
   */
  function _canClaimWithdrawal(address enjoyoorsVault, uint256 requestId) internal view returns (bool) {
    IEnjoyoorsVault.WithdrawalRequest memory request = IEnjoyoorsVault(enjoyoorsVault).getWithdrawalRequestById(
      requestId
    );

    return request.timestamp != 0 && request.timestamp + withdrawalPeriodSeconds <= block.timestamp;
  }
}
