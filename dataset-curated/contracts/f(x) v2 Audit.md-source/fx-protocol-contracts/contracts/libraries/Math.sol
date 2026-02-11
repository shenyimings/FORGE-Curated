// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

library Math {
  enum Rounding {
    Up,
    Down
  }

  /// @dev Internal return the value of min(a, b).
  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  /// @dev Internal return the value of max(a, b).
  function max(uint256 a, uint256 b) internal pure returns (uint256) {
    return a > b ? a : b;
  }

  /// @dev Internal return the value of a * b / c, with rounding.
  function mulDiv(uint256 a, uint256 b, uint256 c, Rounding rounding) internal pure returns (uint256) {
    return rounding == Rounding.Down ? mulDivDown(a, b, c) : mulDivUp(a, b, c);
  }

  /// @dev Internal return the value of ceil(a * b / c).
  function mulDivUp(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
    return (a * b + c - 1) / c;
  }

  /// @dev Internal return the value of floor(a * b / c).
  function mulDivDown(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
    return (a * b) / c;
  }
}
