// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;
pragma abicoder v2;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IReservePool } from "../interfaces/IReservePool.sol";

contract ReservePool is AccessControl, IReservePool {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;

  /**********
   * Errors *
   **********/

  /// @dev Thrown the bonus ratio is too large.
  error ErrorRatioTooLarge();

  /// @dev Thrown when add an already added rebalance pool.
  error ErrorRebalancePoolAlreadyAdded();

  /// @dev Thrown when remove an unknown rebalance pool.
  error ErrorRebalancePoolNotAdded();

  /// @dev Thrown when the caller is not `FxOmniVault`.
  error ErrorCallerNotPoolManager();

  /*************
   * Constants *
   *************/

  /// @dev The address of `PoolManager` contract.
  address public immutable poolManager;

  /*************
   * Variables *
   *************/

  /***************
   * Constructor *
   ***************/

  constructor(address admin, address _poolManager) {
    poolManager = _poolManager;

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IReservePool
  function getBalance(address token) external view returns (uint256) {
    return _getBalance(token);
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  /// @inheritdoc IReservePool
  function requestBonus(address _token, address _recipient, uint256 _bonus) external {
    if (_msgSender() != poolManager) revert ErrorCallerNotPoolManager();

    uint256 _balance = _getBalance(_token);

    if (_bonus > _balance) {
      _bonus = _balance;
    }
    if (_bonus > 0) {
      _transferToken(_token, _recipient, _bonus);

      emit RequestBonus(_token, _recipient, _bonus);
    }
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Withdraw dust assets in this contract.
  /// @param _token The address of token to withdraw.
  /// @param _recipient The address of token receiver.
  function withdrawFund(address _token, uint256 amount, address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _transferToken(_token, _recipient, amount);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to return the balance of the token in this contract.
  /// @param _token The address of token to query.
  function _getBalance(address _token) internal view returns (uint256) {
    if (_token == address(0)) {
      return address(this).balance;
    } else {
      return IERC20(_token).balanceOf(address(this));
    }
  }

  /// @dev Internal function to transfer ETH or ERC20 tokens to some `_receiver`.
  ///
  /// @param _token The address of token to transfer, user `_token=address(0)` if transfer ETH.
  /// @param _receiver The address of token receiver.
  /// @param _amount The amount of token to transfer.
  function _transferToken(address _token, address _receiver, uint256 _amount) internal {
    if (_token == address(0)) {
      Address.sendValue(payable(_receiver), _amount);
    } else {
      IERC20(_token).safeTransfer(_receiver, _amount);
    }
  }
}
