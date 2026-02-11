// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract SharedLiquidityGaugeRename {
  uint8 private _initialized;
  bool private _initializing;
  uint256 private _status;
  uint256[49] private __gap_1;
  uint256[50] private __gap_2;
  mapping(address => uint256) private _balances;
  mapping(address => mapping(address => uint256)) private _allowances;
  uint256 private _totalSupply;
  string private _name;
  string private _symbol;

  function rename(string memory name_, string memory symbol_) external {
    _name = name_;
    _symbol = symbol_;
  }
}
