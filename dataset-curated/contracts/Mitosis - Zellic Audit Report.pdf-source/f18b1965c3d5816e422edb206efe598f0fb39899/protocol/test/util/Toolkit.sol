// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';

import { IAccessControl } from '@oz/access/IAccessControl.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { ERC1967Utils } from '@oz/proxy/ERC1967/ERC1967Utils.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { OwnableUpgradeable } from '@ozu/access/OwnableUpgradeable.sol';

import { ERC1967Factory } from '@solady/utils/ERC1967Factory.sol';

import { Pausable } from '../../src/lib/Pausable.sol';
import { StdError } from '../../src/lib/StdError.sol';

contract Toolkit is Test {
  using SafeCast for uint256;

  // erc1967

  function _erc1967Impl(address target) internal view returns (address) {
    return address(uint160(uint256(vm.load(target, ERC1967Utils.IMPLEMENTATION_SLOT))));
  }

  function _erc1967Admin(address target) internal view returns (address) {
    return address(uint160(uint256(vm.load(target, ERC1967Utils.ADMIN_SLOT))));
  }

  function _erc1967Beacon(address target) internal view returns (address) {
    return address(uint160(uint256(vm.load(target, ERC1967Utils.BEACON_SLOT))));
  }

  // proxy

  function _proxy(address impl) internal returns (address) {
    return address(new ERC1967Proxy(impl, bytes('')));
  }

  function _proxy(address impl, bytes memory data) internal returns (address) {
    return address(new ERC1967Proxy(impl, data));
  }

  function _proxy(address impl, bytes memory data, uint256 value) internal returns (address) {
    return address(new ERC1967Proxy{ value: value }(impl, data));
  }

  // time

  function _now() internal view returns (uint256) {
    return block.timestamp;
  }

  function _now48() internal view returns (uint48) {
    return block.timestamp.toUint48();
  }

  // OwnableUpgradeable

  function _errOwnableUnauthorizedAccount(address sender) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender);
  }

  // Pausable

  function _errPaused(bytes4 sig) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(Pausable.Pausable__Paused.selector, sig);
  }

  // StdError

  function _errUnauthorized() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(StdError.Unauthorized.selector);
  }

  function _errZeroToAddress() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(StdError.ZeroAddress.selector, 'to');
  }

  function _errZeroAmount() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(StdError.ZeroAmount.selector);
  }

  function _errInvalidAddress(string memory context) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(StdError.InvalidAddress.selector, context);
  }

  function _errInvalidParameter(string memory context) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(StdError.InvalidParameter.selector, context);
  }

  function _errNotFound(string memory context) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(StdError.NotFound.selector, context);
  }

  function _errNotSupported() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(StdError.NotSupported.selector);
  }

  function _errAccessControlUnauthorized(address account, bytes32 role) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role);
  }
}
