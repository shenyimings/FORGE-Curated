// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

library StdError {
  error Halted();
  error Unauthorized();
  error NotFound(string description);
  error NotImplemented();
  error NotSupported();

  error InvalidId(string description);
  error InvalidAddress(string description);
  error InvalidParameter(string description);
  error ZeroAmount();
  error ZeroAddress(string description);
  error EnumOutOfBounds(uint8 max, uint8 actual);
}
