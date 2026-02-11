// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ERC4626DecoderAndSanitizer } from './ERC4626DecoderAndSanitizer.sol';

contract ERC7540DecoderAndSanitizer is ERC4626DecoderAndSanitizer {
  function requestDeposit(uint256, address controller, address owner)
    external
    pure
    returns (bytes memory addressesFound)
  {
    addressesFound = abi.encodePacked(controller, owner);
  }

  function requestRedeem(uint256, address controller, address owner)
    external
    pure
    returns (bytes memory addressesFound)
  {
    addressesFound = abi.encodePacked(controller, owner);
  }
}
