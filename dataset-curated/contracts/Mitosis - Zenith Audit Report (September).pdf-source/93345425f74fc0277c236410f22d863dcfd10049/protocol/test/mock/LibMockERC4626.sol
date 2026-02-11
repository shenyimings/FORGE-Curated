// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC4626 } from '@oz/interfaces/IERC4626.sol';

import { MockContract } from '../util/MockContract.sol';
import { LibMockERC20 } from './LibMockERC20.sol';

library LibMockERC4626 {
  using LibMockERC20 for address;

  function _to(address mock) private pure returns (MockContract) {
    return MockContract(payable(mock));
  }

  function initMockERC4626(address mock) internal {
    mock.initMockERC20();

    _to(mock).setCall(IERC4626.deposit.selector);
    _to(mock).setCall(IERC4626.mint.selector);
    _to(mock).setCall(IERC4626.withdraw.selector);
    _to(mock).setCall(IERC4626.redeem.selector);

    _to(mock).setStatic(IERC4626.asset.selector);
    _to(mock).setStatic(IERC4626.totalAssets.selector);
    _to(mock).setStatic(IERC4626.convertToShares.selector);
    _to(mock).setStatic(IERC4626.convertToAssets.selector);
    _to(mock).setStatic(IERC4626.maxDeposit.selector);
    _to(mock).setStatic(IERC4626.maxMint.selector);
    _to(mock).setStatic(IERC4626.maxWithdraw.selector);
    _to(mock).setStatic(IERC4626.maxRedeem.selector);
    _to(mock).setStatic(IERC4626.previewDeposit.selector);
    _to(mock).setStatic(IERC4626.previewMint.selector);
    _to(mock).setStatic(IERC4626.previewWithdraw.selector);
    _to(mock).setStatic(IERC4626.previewRedeem.selector);
  }

  // ================================================= VIEW FUNCTIONS ================================================= //

  function setRetERC4626Asset(address mock, address asset) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.asset, ());
    _to(mock).setRet(data, false, abi.encode(asset));
    return mock;
  }

  function setRetERC4626TotalAssets(address mock, uint256 totalAssets) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.totalAssets, ());
    _to(mock).setRet(data, false, abi.encode(totalAssets));
    return mock;
  }

  function setRetERC4626ConvertToShares(address mock, uint256 assets, uint256 shares) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.convertToShares, (assets));
    _to(mock).setRet(data, false, abi.encode(shares));
    return mock;
  }

  function setRetERC4626ConvertToAssets(address mock, uint256 shares, uint256 assets) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.convertToAssets, (shares));
    _to(mock).setRet(data, false, abi.encode(assets));
    return mock;
  }

  function setRetERC4626MaxDeposit(address mock, address receiver, uint256 maxAssets) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.maxDeposit, (receiver));
    _to(mock).setRet(data, false, abi.encode(maxAssets));
    return mock;
  }

  function setRetERC4626MaxMint(address mock, address receiver, uint256 maxShares) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.maxMint, (receiver));
    _to(mock).setRet(data, false, abi.encode(maxShares));
    return mock;
  }

  function setRetERC4626MaxWithdraw(address mock, address owner, uint256 maxAssets) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.maxWithdraw, (owner));
    _to(mock).setRet(data, false, abi.encode(maxAssets));
    return mock;
  }

  function setRetERC4626MaxRedeem(address mock, address owner, uint256 maxShares) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.maxRedeem, (owner));
    _to(mock).setRet(data, false, abi.encode(maxShares));
    return mock;
  }

  function setRetERC4626PreviewDeposit(address mock, uint256 assets, uint256 shares) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.previewDeposit, (assets));
    _to(mock).setRet(data, false, abi.encode(shares));
    return mock;
  }

  function setRetERC4626PreviewMint(address mock, uint256 shares, uint256 assets) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.previewMint, (shares));
    _to(mock).setRet(data, false, abi.encode(assets));
    return mock;
  }

  function setRetERC4626PreviewWithdraw(address mock, uint256 assets, uint256 shares) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.previewWithdraw, (assets));
    _to(mock).setRet(data, false, abi.encode(shares));
    return mock;
  }

  function setRetERC4626PreviewRedeem(address mock, uint256 shares, uint256 assets) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.previewRedeem, (shares));
    _to(mock).setRet(data, false, abi.encode(assets));
    return mock;
  }

  // ================================================= MUTATIVE FUNCTIONS ================================================= //

  function setRetERC4626Deposit(address mock, uint256 assets, address receiver, uint256 shares)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IERC4626.deposit, (assets, receiver));
    _to(mock).setRet(data, false, abi.encode(shares));
    return mock;
  }

  function assertERC4626Deposit(address mock, uint256 assets, address receiver) internal view returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.deposit, (assets, receiver));
    _to(mock).assertLastCall(data);
    return mock;
  }

  function setRetERC4626Mint(address mock, uint256 shares, address receiver, uint256 assets) internal returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.mint, (shares, receiver));
    _to(mock).setRet(data, false, abi.encode(assets));
    return mock;
  }

  function assertERC4626Mint(address mock, uint256 shares, address receiver) internal view returns (address) {
    bytes memory data = abi.encodeCall(IERC4626.mint, (shares, receiver));
    _to(mock).assertLastCall(data);
    return mock;
  }

  function setRetERC4626Withdraw(address mock, uint256 assets, address receiver, address owner, uint256 shares)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IERC4626.withdraw, (assets, receiver, owner));
    _to(mock).setRet(data, false, abi.encode(shares));
    return mock;
  }

  function assertERC4626Withdraw(address mock, uint256 assets, address receiver, address owner)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IERC4626.withdraw, (assets, receiver, owner));
    _to(mock).assertLastCall(data);
    return mock;
  }

  function setRetERC4626Redeem(address mock, uint256 shares, address receiver, address owner, uint256 assets)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IERC4626.redeem, (shares, receiver, owner));
    _to(mock).setRet(data, false, abi.encode(assets));
    return mock;
  }

  function assertERC4626Redeem(address mock, uint256 shares, address receiver, address owner)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IERC4626.redeem, (shares, receiver, owner));
    _to(mock).assertLastCall(data);
    return mock;
  }
}
