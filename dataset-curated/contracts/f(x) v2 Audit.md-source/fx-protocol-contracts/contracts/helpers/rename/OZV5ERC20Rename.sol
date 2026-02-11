// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract OZV5ERC20Rename {
  /// @custom:storage-location erc7201:openzeppelin.storage.ERC20
  struct ERC20Storage {
    mapping(address account => uint256) _balances;
    mapping(address account => mapping(address spender => uint256)) _allowances;
    uint256 _totalSupply;
    string _name;
    string _symbol;
  }

  // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

  function _getERC20Storage() private pure returns (ERC20Storage storage $) {
    assembly {
      $.slot := ERC20StorageLocation
    }
  }

  function rename(string memory name_, string memory symbol_) external {
    ERC20Storage storage $ = _getERC20Storage();
    $._name = name_;
    $._symbol = symbol_;
  }
}
