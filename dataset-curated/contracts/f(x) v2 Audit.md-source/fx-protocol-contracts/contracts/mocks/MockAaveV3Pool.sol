// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IAaveV3Pool } from "../interfaces/Aave/IAaveV3Pool.sol";

contract MockAaveV3Pool is IAaveV3Pool {
  uint128 public variableBorrowRate;
  uint256 public reserveNormalizedVariableDebt;

  constructor(uint128 _variableBorrowRate) {
    variableBorrowRate = _variableBorrowRate;
  }

  function setVariableBorrowRate(uint128 _variableBorrowRate) external {
    variableBorrowRate = _variableBorrowRate;
  }

  function setReserveNormalizedVariableDebt(uint256 _reserveNormalizedVariableDebt) external {
    reserveNormalizedVariableDebt = _reserveNormalizedVariableDebt;
  }

  function getReserveData(address) external view returns (ReserveDataLegacy memory result) {
    result.currentVariableBorrowRate = variableBorrowRate;
  }

  function getReserveNormalizedVariableDebt(address) external view returns (uint256) {
    return reserveNormalizedVariableDebt;
  }

  function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external override {}

  function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {}
}
