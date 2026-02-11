// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import './Pauses.sol';
import './Setup.sol';
import './TokenListing.sol';
import '../../libraries/Asserts.sol';

/// @title Abstract contract joining all other ones with role-based access functionality
abstract contract Access is Pauses, Setup, TokenListing {
  using Asserts for address;

  /// @param defaultAdmin Address which will be able to grant and revoke contract roles
  constructor(address defaultAdmin) {
    defaultAdmin.assertNotZeroAddress();
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
  }
}
