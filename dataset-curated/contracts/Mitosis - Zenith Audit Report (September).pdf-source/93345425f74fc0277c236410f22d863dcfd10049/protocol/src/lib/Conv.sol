// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Strings } from '@oz/utils/Strings.sol';

import { StdError } from './StdError.sol';

library Conv {
  function toBytes32(address addr) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(addr)));
  }

  /// @dev This function must be used to only for inbound hyperlane messages.
  ///      It is not safe to use for chains that are using 32-length bytes address.
  function toAddress(bytes32 bz) internal pure returns (address) {
    require(uint256(bz) <= type(uint160).max, StdError.InvalidAddress(Strings.toHexString(uint256(bz))));
    return address(uint160(uint256(bz)));
  }
}
