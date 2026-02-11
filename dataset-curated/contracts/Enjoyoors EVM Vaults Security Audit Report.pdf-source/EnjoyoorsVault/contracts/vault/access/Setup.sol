// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import '../EnjoyoorsVaultBase.sol';
import '../../libraries/Asserts.sol';

/// @title Abstract contract for Enjoyoors vault settings
abstract contract Setup is AccessControl, EnjoyoorsVaultBase {
  using Asserts for address;

  /// @notice Hash of role with changing contract params rights
  bytes32 public constant SETUP_ROLE = keccak256('SETUP_ROLE');

  /**
   * @notice Emitted when maximum `token` capitalization limit was increased
   * @param token Token which maximum capitalization limit was increased
   * @param delta Value added to the limit
   */
  event SupplyLimitIncreased(address indexed token, uint256 delta);
  /**
   * @notice Emitted when maximum `token` capitalization limit was decreased
   * @param token Token which maximum capitalization limit was decreased
   * @param delta Value subtracted from the limit
   */
  event SupplyLimitDecreased(address indexed token, uint256 delta);
  /**
   * @notice Emitted when new minimal allowed deposit is set for `token`
   * @param token Token which minimal deposit is changed
   * @param _old Old minimal deposit amount
   * @param _new New minimal deposit amount
   */
  event MinDepositChanged(address indexed token, uint256 _old, uint256 _new);
  /**
   * @notice Emitted when address of `EnjoyoorsWithdrawalApprover` contract was changed
   * @param _old Old `EnjoyoorsWithdrawalApprover` contract address
   * @param _new New `EnjoyoorsWithdrawalApprover` contract address
   */
  event WithdrawalApproverChanged(address _old, address _new);

  /// @notice Revert reason if maximum token capitalization limit exceeds as the result of its decrease
  /// @param supplyLeft Maximum value token capitalization can be decreased by
  error SupplyLimitDecreaseFailed(uint256 supplyLeft);
  /// @notice Revert reason if an attempt to set wrong `EnjoyoorsWithdrawalApprover` contract occurs
  error WrongApproverAddress();

  /**
   * @notice Requires `SETUP_ROLE` rights. Increases listed `token` maximum capitalization
   * @param token Token which maximum capitalization limit is increased
   * @param delta Value to be added to the limit
   */
  function increaseSupplyLimit(address token, uint256 delta) external {
    _increaseSupplyLimit(token, delta);
  }

  /**
   * @notice Requires `SETUP_ROLE` rights. Decreases listed `token` maximum capitalization
   * @param token Token which maximum capitalization limit is decreased
   * @param delta Value to be subtracted from the limit
   */
  function decreaseSupplyLimit(address token, uint256 delta) external {
    _decreaseSupplyLimit(token, delta);
  }

  /**
   * @notice Requires `SETUP_ROLE` rights. Changes listed `token` minimal allowed deposit
   * @param token Token which minimal allowed deposit amount is changed
   * @param newMinDeposit New `token` minimal allowed deposit amount
   */
  function changeMinDeposit(address token, uint256 newMinDeposit) external {
    _changeMinDeposit(token, newMinDeposit);
  }

  /**
   * @notice Requires `SETUP_ROLE` rights. Changes `EnjoyoorsWithdrawalApprover` contract address
   * @param newWithdrawalApprover new `EnjoyoorsWithdrawalApprover` contract address
   */
  function changeWithdrawalApprover(address newWithdrawalApprover) external {
    _changeWithdrawalApprover(newWithdrawalApprover);
  }

  /**
   * @notice Internal method with increasing capitalization limit implementation
   * @param token Token which maximum capitalization limit is increased
   * @param delta Value to be added to the limit
   */
  function _increaseSupplyLimit(address token, uint256 delta) private onlyRole(SETUP_ROLE) onlyWhitelistedToken(token) {
    supplyTillLimit[token] += delta;
    emit SupplyLimitIncreased(token, delta);
  }

  /**
   * @notice Internal method with decreasing capitalization limit implementation
   * @param token Token which maximum capitalization limit is decreased
   * @param delta Value to be subtracted from the limit
   */
  function _decreaseSupplyLimit(address token, uint256 delta) private onlyRole(SETUP_ROLE) onlyWhitelistedToken(token) {
    uint256 supplyLeft = supplyTillLimit[token];
    if (supplyLeft < delta) revert SupplyLimitDecreaseFailed(supplyLeft);

    supplyTillLimit[token] -= delta;
    emit SupplyLimitDecreased(token, delta);
  }

  /**
   * @notice Internal method with changing minimal allowed deposit implementation
   * @param token Token which minimal allowed deposit amount is changed
   * @param newMinDeposit New `token` minimal allowed deposit amount
   */
  function _changeMinDeposit(
    address token,
    uint256 newMinDeposit
  ) private onlyRole(SETUP_ROLE) onlyWhitelistedToken(token) {
    uint256 _old = minDeposit[token];
    minDeposit[token] = newMinDeposit;
    emit MinDepositChanged(token, _old, newMinDeposit);
  }

  /**
   * @notice Internal method with implementation of `EnjoyoorsWithdrawalApprover` contract address replacement
   * @param newWithdrawalApprover new `EnjoyoorsWithdrawalApprover` contract address
   */
  function _changeWithdrawalApprover(address newWithdrawalApprover) private onlyRole(SETUP_ROLE) {
    newWithdrawalApprover.assertNotZeroAddress();
    if (!IERC165(newWithdrawalApprover).supportsInterface(type(IEnjoyoorsWithdrawalApprover).interfaceId)) {
      revert WrongApproverAddress();
    }

    address oldWithdrawalApprover = address(withdrawalApprover);
    if (oldWithdrawalApprover == newWithdrawalApprover) revert WrongApproverAddress();

    withdrawalApprover = IEnjoyoorsWithdrawalApprover(newWithdrawalApprover);
    emit WithdrawalApproverChanged(oldWithdrawalApprover, newWithdrawalApprover);
  }
}
