// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import '@openzeppelin/contracts/access/AccessControl.sol';

import '../EnjoyoorsVaultBase.sol';

/// @title Abstract contract for user actions pausing management
abstract contract Pauses is AccessControl, EnjoyoorsVaultBase {
  /**
   * @notice Emitted when withdrawal claims of given `token` get paused
   * @param token Token which withdrawal claims get paused
   */
  event PauseClaims(address token);
  /**
   * @notice Emitted when deposits of given `token` get paused
   * @param token Token which deposits get paused
   */
  event PauseDeposits(address token);
  /**
   * @notice Emitted when withdrawal request submissions of given `token` get paused
   * @param token Token which withdrawal request submissions get paused
   */
  event PauseWithdrawals(address token);
  /**
   * @notice Emitted when withdrawal claims of given `token` are resumed
   * @param token Token which withdrawal claims are resumed
   */
  event ResumeClaims(address token);
  /**
   * @notice Emitted when deposits of given `token` are resumed
   * @param token Token which deposits are resumed
   */
  event ResumeDeposits(address token);
  /**
   * @notice Emitted when withdrawal request submission of given `token` is resumed
   * @param token Token which withdrawal request submission is resumed
   */
  event ResumeWithdrawals(address token);

  /// @notice Revert reason of `whenClaimsNotPaused` assertion
  error ClaimsPaused();
  /// @notice Revert reason of `whenDepositsNotPaused` assertion
  error DepositsPaused();
  /// @notice Revert reason of `whenWithdrawalsNotPaused` assertion
  error WithdrawalsPaused();
  /// @notice Revert reason if an attempt to resume already active withdrawal claims occurs
  error ClaimsAlreadyActive();
  /// @notice Revert reason if an attempt to resume already active deposits occurs
  error DepositsAlreadyActive();
  /// @notice Revert reason if an attempt to resume already active withdrawal submission occurs
  error WithdrawalsAlreadyActive();

  /// @notice Mapping which stores token deposits pause status
  mapping(address token => bool) public depositsPaused;
  /// @notice Mapping which stores token withdrawal request submissions pause status
  mapping(address token => bool) public withdrawalsPaused;
  /// @notice Mapping which stores token withdrawal claims pause status
  mapping(address token => bool) public claimsPaused;

  /// @notice Hash of role with pausing deposits rights
  bytes32 public constant DEPOSIT_PAUSE_ROLE = keccak256('DEPOSIT_PAUSE_ROLE');
  /// @notice Hash of role with pausing withdrawals rights
  bytes32 public constant WITHDRAWAL_PAUSE_ROLE = keccak256('WITHDRAWAL_PAUSE_ROLE');
  /// @notice Hash of role with pausing claims rights
  bytes32 public constant CLAIM_PAUSE_ROLE = keccak256('CLAIM_PAUSE_ROLE');
  /// @notice Hash of role with resuming deposits rights
  bytes32 public constant DEPOSIT_RESUME_ROLE = keccak256('DEPOSIT_RESUME_ROLE');
  /// @notice Hash of role with resuming withdrawals rights
  bytes32 public constant WITHDRAWAL_RESUME_ROLE = keccak256('WITHDRAWAL_RESUME_ROLE');
  /// @notice Hash of role with resuming claims rights
  bytes32 public constant CLAIM_RESUME_ROLE = keccak256('CLAIM_RESUME_ROLE');

  /**
   * @notice Modifier for `token` deposits-not-paused assertion
   * @param token Token which deposits status to assert
   */
  modifier whenDepositsNotPaused(address token) {
    _whenDepositsNotPaused(token);
    _;
  }

  /**
   * @notice Modifier for `token` withdrawal-not-paused assertion
   * @param token Token which withdrawal requests submission status to assert
   */
  modifier whenWithdrawalsNotPaused(address token) {
    _whenWithdrawalsNotPaused(token);
    _;
  }

  /**
   * @notice Requires `DEPOSIT_PAUSE_ROLE` rights. Pauses given `token` deposits
   * @dev Reverts if token is not listed or if `token` deposits are already paused
   * @param token Token which deposits are getting paused
   */
  function pauseDeposit(
    address token
  ) external onlyRole(DEPOSIT_PAUSE_ROLE) onlyWhitelistedToken(token) whenDepositsNotPaused(token) {
    depositsPaused[token] = true;
    emit PauseDeposits(token);
  }

  /**
   * @notice Requires `WITHDRAWAL_PAUSE_ROLE` rights. Pauses given `token` withdrawal request submissions
   * @dev Reverts if token is not listed or if `token` withdrawal requests are already paused
   * @param token Token which withdrawal requests are getting paused
   */
  function pauseWithdrawal(
    address token
  ) external onlyRole(WITHDRAWAL_PAUSE_ROLE) onlyWhitelistedToken(token) whenWithdrawalsNotPaused(token) {
    withdrawalsPaused[token] = true;
    emit PauseWithdrawals(token);
  }

  /**
   * @notice Requires `CLAIM_PAUSE_ROLE` rights. Pauses given `token` withdrawals claiming
   * @dev Reverts if token is not listed or if `token` withdrawals claiming is already paused
   * @param token Token which withdrawals claiming is getting paused
   */
  function pauseClaim(address token) external onlyRole(CLAIM_PAUSE_ROLE) onlyWhitelistedToken(token) {
    _whenClaimsNotPaused(token);
    claimsPaused[token] = true;
    emit PauseClaims(token);
  }

  /**
   * @notice Requires `DEPOSIT_RESUME_ROLE` rights. Activates given `token` deposits
   * @dev Reverts if token is not listed or if `token` deposits are already active
   * @param token Token which deposits are getting activated
   */
  function resumeDeposit(address token) external onlyRole(DEPOSIT_RESUME_ROLE) onlyWhitelistedToken(token) {
    if (!depositsPaused[token]) revert DepositsAlreadyActive();
    depositsPaused[token] = false;
    emit ResumeDeposits(token);
  }

  /**
   * @notice Requires `WITHDRAWAL_RESUME_ROLE` rights. Activates given `token` withdrawal request submissions
   * @dev Reverts if token is not listed or if `token` withdrawal requests are already active
   * @param token Token which withdrawal requests are getting activated
   */
  function resumeWithdrawal(address token) external onlyRole(WITHDRAWAL_RESUME_ROLE) onlyWhitelistedToken(token) {
    if (!withdrawalsPaused[token]) revert WithdrawalsAlreadyActive();
    withdrawalsPaused[token] = false;
    emit ResumeWithdrawals(token);
  }

  /**
   * @notice Requires `CLAIM_RESUME_ROLE` rights. Activates given `token` withdrawals claiming
   * @dev Reverts if token is not listed or if `token` withdrawals claiming are already active
   * @param token Token which withdrawals claiming is getting activated
   */
  function resumeClaim(address token) external onlyRole(CLAIM_RESUME_ROLE) onlyWhitelistedToken(token) {
    if (!claimsPaused[token]) revert ClaimsAlreadyActive();
    claimsPaused[token] = false;
    emit ResumeClaims(token);
  }

  /**
   * @notice Internal method for `token` deposits-not-paused assertion
   * @param token Token which deposits status to assert
   */
  function _whenDepositsNotPaused(address token) internal view {
    if (depositsPaused[token]) revert DepositsPaused();
  }

  /**
   * @notice Internal method for `token` withdrawal-not-paused assertion
   * @param token Token which withdrawal requests submission status to assert
   */
  function _whenWithdrawalsNotPaused(address token) internal view {
    if (withdrawalsPaused[token]) revert WithdrawalsPaused();
  }

  /**
   * @notice Internal method for `token` claims-not-paused assertion
   * @param token Token which withdrawal claiming status to assert
   */
  function _whenClaimsNotPaused(address token) internal view {
    if (claimsPaused[token]) revert ClaimsPaused();
  }
}
