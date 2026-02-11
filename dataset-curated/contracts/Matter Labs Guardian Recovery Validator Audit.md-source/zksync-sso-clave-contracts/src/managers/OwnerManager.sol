// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SsoStorage } from "../libraries/SsoStorage.sol";
import { Errors } from "../libraries/Errors.sol";
import { SelfAuth } from "../auth/SelfAuth.sol";
import { IOwnerManager } from "../interfaces/IOwnerManager.sol";

/**
 * @title Manager contract for owners
 * @notice Abstract contract for managing the owners of the account
 * @dev K1 Owners are secp256k1 addresses
 * @dev Owners are stored in an enumerable set
 * @author https://getclave.io
 */
abstract contract OwnerManager is IOwnerManager, SelfAuth {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @inheritdoc IOwnerManager
  function addK1Owner(address addr) external override onlySelf {
    _addK1Owner(addr);
  }

  /// @inheritdoc IOwnerManager
  function removeK1Owner(address addr) external override onlySelf {
    _removeK1Owner(addr);
  }

  /// @inheritdoc IOwnerManager
  function isK1Owner(address addr) external view override returns (bool) {
    return _isK1Owner(addr);
  }

  /// @inheritdoc IOwnerManager
  function listK1Owners() external view override returns (address[] memory k1OwnerList) {
    k1OwnerList = _k1Owners().values();
  }

  // Should not be set to private as it is called from SsoAccount's initialize
  function _addK1Owner(address addr) internal {
    if (!_k1Owners().add(addr)) {
      revert Errors.OWNER_ALREADY_EXISTS(addr);
    }

    emit K1OwnerAdded(addr);
  }

  function _removeK1Owner(address addr) private {
    if (!_k1Owners().remove(addr)) {
      revert Errors.OWNER_NOT_FOUND(addr);
    }

    emit K1OwnerRemoved(addr);
  }

  function _isK1Owner(address addr) internal view returns (bool) {
    return _k1Owners().contains(addr);
  }

  function _k1Owners() private view returns (EnumerableSet.AddressSet storage k1Owners) {
    k1Owners = SsoStorage.layout().k1Owners;
  }
}
