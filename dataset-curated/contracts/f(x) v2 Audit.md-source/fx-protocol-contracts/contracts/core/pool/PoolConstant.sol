// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPool } from "../../interfaces/IPool.sol";

abstract contract PoolConstant is IPool {
  /*************
   * Constants *
   *************/

  /// @dev The role for emergency operations.
  bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

  /// @dev The value of minimum collateral.
  int256 internal constant MIN_COLLATERAL = 1e9;

  /// @dev The value of minimum debts.
  int256 internal constant MIN_DEBT = 1e9;

  /// @dev The precision used for various calculation.
  uint256 internal constant PRECISION = 1e18;

  /// @dev The precision used for fee ratio calculation.
  uint256 internal constant FEE_PRECISION = 1e9;

  /// @dev bit operation related constants
  uint256 internal constant E60 = 2 ** 60; // 2^60
  uint256 internal constant E96 = 2 ** 96; // 2^96

  uint256 internal constant X60 = 0xfffffffffffffff; // 2^60 - 1
  uint256 internal constant X96 = 0xffffffffffffffffffffffff; // 2^96 - 1

  /***********************
   * Immutable Variables *
   ***********************/

  /// @inheritdoc IPool
  address public immutable fxUSD;

  /// @inheritdoc IPool
  address public immutable poolManager;

  /// @inheritdoc IPool
  address public immutable pegKeeper;
}
