// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../access/Access.sol';
import '../../libraries/Asserts.sol';

/// @title Abstract contract with Enjoyoors vaults deposit functionality
abstract contract EnjoyoorsVaultDeposits is Access {
  using SafeERC20 for IERC20;
  using Asserts for uint256;

  /**
   * @notice Emitted in case of successful deposit call
   * @param token Token that was transferred into the vault
   * @param user User who performed deposit
   * @param amount Deposit amount
   */
  event Deposit(address indexed token, address indexed user, uint256 amount);

  /**
   * @notice Revert reason if deposit amount exceeds maximum token capitalization
   * @param tillLimit Max deposit allowed
   */
  error ExceedsLimit(uint256 tillLimit);
  /**
   * @notice Revert reason if deposit doesn't surpass minimal allowed deposit amount
   * @param minDeposit Minimal allowed deposit amount
   */
  error LessThanMinDeposit(uint256 minDeposit);

  /**
   * @notice Internal method with deposits implementation
   * @param token Token to deposit. Token must be listed in vault
   * @param amount Amount to deposit
   */
  function _deposit(address token, uint256 amount) internal onlyWhitelistedToken(token) whenDepositsNotPaused(token) {
    uint256 minAllowedDeposit = minDeposit[token];
    if (minAllowedDeposit == 0) amount.assertNotZeroAmount();
    if (amount < minAllowedDeposit) revert LessThanMinDeposit(minAllowedDeposit);

    uint256 tillLimit = supplyTillLimit[token];
    if (amount > tillLimit) revert ExceedsLimit(tillLimit);

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    totalSupply[token] += amount;
    userSupply[token][msg.sender] += amount;
    supplyTillLimit[token] -= amount;

    emit Deposit(token, msg.sender, amount);
  }
}
