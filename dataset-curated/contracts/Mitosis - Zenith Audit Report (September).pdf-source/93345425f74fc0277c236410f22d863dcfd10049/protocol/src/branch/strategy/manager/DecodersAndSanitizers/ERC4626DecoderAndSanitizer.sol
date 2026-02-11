// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { BaseDecoderAndSanitizer } from './BaseDecoderAndSanitizer.sol';

contract ERC4626DecoderAndSanitizer is BaseDecoderAndSanitizer {
  function deposit(uint256, address receiver) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(receiver);
  }

  function mint(uint256, address receiver) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(receiver);
  }

  function withdraw(uint256, address receiver, address owner) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(receiver, owner);
  }

  function redeem(uint256, address receiver, address owner) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(receiver, owner);
  }
}
