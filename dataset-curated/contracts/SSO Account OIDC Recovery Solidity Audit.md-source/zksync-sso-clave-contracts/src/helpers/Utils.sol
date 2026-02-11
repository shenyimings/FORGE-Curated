// SPDX-License-Identifier: MIT

import { Errors } from "../libraries/Errors.sol";

/// @title Utility functions
/// @dev Utility functions for used in ZKsync SSO contracts
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
library Utils {
  /// @dev Safely casts a uint256 to an address.
  /// @dev Revert if the value exceeds the maximum size for an address (160 bits).
  function safeCastToAddress(uint256 _value) internal pure returns (address) {
    if (_value > type(uint160).max) {
      revert Errors.ADDRESS_CAST_OVERFLOW(_value);
    }
    return address(uint160(_value));
  }
}
