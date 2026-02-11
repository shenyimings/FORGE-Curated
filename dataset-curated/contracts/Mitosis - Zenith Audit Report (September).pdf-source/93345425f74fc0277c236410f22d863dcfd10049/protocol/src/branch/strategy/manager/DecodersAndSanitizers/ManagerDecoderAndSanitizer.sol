// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { BaseDecoderAndSanitizer } from './BaseDecoderAndSanitizer.sol';

contract ManagerDecoderAndSanitizer is BaseDecoderAndSanitizer {
  function deposit(uint256) external pure returns (bytes memory addressesFound) { }

  function withdraw(uint256, address receiver) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(receiver);
  }
}
