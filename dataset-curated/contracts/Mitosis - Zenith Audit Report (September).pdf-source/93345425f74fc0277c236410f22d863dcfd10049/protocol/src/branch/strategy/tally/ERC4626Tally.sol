// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC4626 } from '@oz/interfaces/IERC4626.sol';

import { StdTally } from './StdTally.sol';

contract ERC4626Tally is StdTally {
  IERC4626 public immutable vault;

  constructor(IERC4626 vault_) {
    vault = vault_;
  }

  function _totalBalance(bytes memory) internal view override returns (uint256) {
    return vault.balanceOf(msg.sender);
  }
}
