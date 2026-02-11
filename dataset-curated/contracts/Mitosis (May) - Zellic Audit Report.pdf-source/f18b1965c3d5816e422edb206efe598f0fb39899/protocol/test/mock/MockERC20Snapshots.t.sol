// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20Upgradeable } from '@ozu/token/ERC20/ERC20Upgradeable.sol';

contract MockERC20Snapshots is ERC20Upgradeable {
  function initialize(string memory name, string memory symbol) external initializer {
    __ERC20_init(name, symbol);
  }

  function mint(address account, uint256 value) external {
    _mint(account, value);
  }
}
