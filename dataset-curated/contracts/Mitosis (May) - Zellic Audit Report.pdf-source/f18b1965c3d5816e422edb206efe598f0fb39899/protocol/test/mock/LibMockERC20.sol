// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';

import { MockContract } from '../util/MockContract.sol';

library LibMockERC20 {
  function _to(address mock) private pure returns (MockContract) {
    return MockContract(payable(mock));
  }

  function initMockERC20(address mock) internal {
    _to(mock).setCall(IERC20.transfer.selector);
    _to(mock).setCall(IERC20.transferFrom.selector);
    _to(mock).setCall(IERC20.approve.selector);

    _to(mock).setStatic(IERC20.allowance.selector);
    _to(mock).setStatic(IERC20.balanceOf.selector);
    _to(mock).setStatic(IERC20.totalSupply.selector);

    _to(mock).setStatic(IERC20Metadata.name.selector);
    _to(mock).setStatic(IERC20Metadata.symbol.selector);
    _to(mock).setStatic(IERC20Metadata.decimals.selector);
  }

  // ================================================= VIEW FUNCTIONS ================================================= //

  function setRetERC20Allowance(address mock, address owner, address spender, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IERC20.allowance, (owner, spender));
    _to(mock).setRet(data, false, abi.encode(amount));
    return mock;
  }

  function setRetERC20BalanceOf(address mock, address account, uint256 amount) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20.balanceOf, (account));
    _to(mock).setRet(data, false, abi.encode(amount));
    return mock;
  }

  function setRetERC20TotalSupply(address mock, uint256 amount) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20.totalSupply, ());
    _to(mock).setRet(data, false, abi.encode(amount));
    return mock;
  }

  function setRetERC20Name(address mock, string memory name) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20Metadata.name, ());
    _to(mock).setRet(data, false, abi.encode(name));
    return mock;
  }

  function setRetERC20Symbol(address mock, string memory symbol) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20Metadata.symbol, ());
    _to(mock).setRet(data, false, abi.encode(symbol));
    return mock;
  }

  function setRetERC20Decimals(address mock, uint8 decimals) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20Metadata.decimals, ());
    _to(mock).setRet(data, false, abi.encode(decimals));
    return mock;
  }

  // ================================================= MUTATIVE FUNCTIONS ================================================= //

  function setRetERC20Transfer(address mock, address to, uint256 amount) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20.transfer, (to, amount));
    _to(mock).setRet(data, false, abi.encode(true));
    return mock;
  }

  function assertERC20Transfer(address mock, address to, uint256 amount) internal view returns (address) {
    bytes memory data = abi.encodeCall(IERC20.transfer, (to, amount));
    _to(mock).assertLastCall(data);
    return mock;
  }

  function setRetERC20TransferFrom(address mock, address from, address to, uint256 amount) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20.transferFrom, (from, to, amount));
    _to(mock).setRet(data, false, abi.encode(true));
    return mock;
  }

  function assertERC20TransferFrom(address mock, address from, address to, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IERC20.transferFrom, (from, to, amount));
    _to(mock).assertLastCall(data);

    return mock;
  }

  function setRetERC20Approve(address mock, address spender, uint256 amount) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC20.approve, (spender, amount));
    _to(mock).setRet(data, false, abi.encode(true));
    return mock;
  }

  function assertERC20Approve(address mock, address spender, uint256 amount) internal view returns (address) {
    bytes memory data = abi.encodeCall(IERC20.approve, (spender, amount));
    _to(mock).assertLastCall(data);
    return mock;
  }
}
