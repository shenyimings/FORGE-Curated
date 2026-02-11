// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../access/Access.sol';
import '../../libraries/Asserts.sol';

/// @title Abstract contract with Enjoyoors vaults withdrawal requests and claims functionality
abstract contract EnjoyoorsVaultWithdrawals is Access {
  using SafeERC20 for IERC20;
  using Asserts for uint256;

  /**
   * @notice Emitted in case of successful withdrawal request submission
   * @param token Token, requested for withdrawal
   * @param user User who requested withdrawal
   * @param requestId Id of submitted request
   * @param amount Amount of `token` requested for withdrawal
   */
  event WithdrawalRequested(address indexed token, address indexed user, uint256 indexed requestId, uint256 amount);
  /**
   * @notice Emitted in case of successful withdrawal request submission
   * @param requestId Id of claimed request
   * @param amount Amount of `token` claimed
   */
  event WithdrawalClaimed(uint256 indexed requestId, uint256 amount);

  /**
   * @notice Revert reason if user has less supply than requested for withdrawal
   * @param userSupply User supply of withdrawal token
   */
  error NotEnoughUserSupply(uint256 userSupply);
  /**
   * @notice Revert reason if an attempt to claim non-existent withdrawal request occurs
   * @param lastRequestId Most recent withdrawal request id
   */
  error WrongWithdrawalRequestId(uint256 lastRequestId);
  /// @notice Revert reason if an attempt of withdrawal double claim occurs
  error AlreadyClaimed();

  /// @notice Most recent withdrawal request id
  uint256 public lastRequestId;
  /// @notice Mapping with all withdrawal requests
  mapping(uint256 requestId => WithdrawalRequest) withdrawalRequests;

  /**
   * @notice Internal method with withdrawal requests implementation
   * @param token Address of vault-listed token
   * @param amount Amount of `token` to withdraw
   * @return requestId Id of this request if successful
   */
  function _requestWithdrawal(
    address token,
    uint256 amount
  ) internal onlyWhitelistedToken(token) whenWithdrawalsNotPaused(token) returns (uint256 requestId) {
    amount.assertNotZeroAmount();

    uint256 _userSupply = userSupply[token][msg.sender];
    if (_userSupply < amount) revert NotEnoughUserSupply(_userSupply);

    WithdrawalRequest memory request = WithdrawalRequest({
      amount: amount,
      token: token,
      user: msg.sender,
      timestamp: uint184(block.timestamp),
      claimed: false
    });
    requestId = ++lastRequestId;
    withdrawalRequests[requestId] = request;

    totalSupply[token] -= amount;
    userSupply[token][msg.sender] -= amount;

    emit WithdrawalRequested(token, msg.sender, requestId, amount);
  }

  /**
   * @notice Internal method with withdrawal claiming implementation
   * @param requestId Id of a request to claim
   * @param approverData Data used by`withdrawalApprover` in a verification process
   * @return token Claimed token address
   * @return amount Claimed `token` amount
   */
  function _claimWithdrawal(
    uint256 requestId,
    bytes calldata approverData
  ) internal returns (address token, uint256 amount) {
    WithdrawalRequest storage request = withdrawalRequests[requestId];

    token = request.token;
    _whenClaimsNotPaused(token);

    amount = request.amount;
    if (amount == 0) revert WrongWithdrawalRequestId(lastRequestId);
    if (request.claimed) revert AlreadyClaimed();

    withdrawalApprover.verifyWithdrawalApproved(requestId, approverData);

    IERC20(token).safeTransfer(request.user, amount);

    request.claimed = true;
    supplyTillLimit[token] += amount;

    emit WithdrawalClaimed(requestId, amount);
  }

  /// @inheritdoc IEnjoyoorsVault
  function getWithdrawalRequestById(uint256 requestId) external view returns (WithdrawalRequest memory) {
    return withdrawalRequests[requestId];
  }
}
