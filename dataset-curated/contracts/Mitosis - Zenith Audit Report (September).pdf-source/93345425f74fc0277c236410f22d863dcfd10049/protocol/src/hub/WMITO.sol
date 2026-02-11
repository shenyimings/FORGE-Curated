// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { WETH } from '@solady/tokens/WETH.sol';

import { Versioned } from '../lib/Versioned.sol';

contract WMITO is WETH, Versioned {
  /// @dev Returns the name of the token.
  function name() public view virtual override returns (string memory) {
    return 'Wrapped MITO';
  }

  /// @dev Returns the symbol of the token.
  function symbol() public view virtual override returns (string memory) {
    return 'WMITO';
  }
}
