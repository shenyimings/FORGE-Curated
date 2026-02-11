// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import { BaseDecoderAndSanitizer } from
  '../../src/branch/strategy/manager/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol';

contract MockTestVaultDecoderAndSanitizer is BaseDecoderAndSanitizer {
  constructor() { }

  function deposit(address account, uint256) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(account);
  }
}
