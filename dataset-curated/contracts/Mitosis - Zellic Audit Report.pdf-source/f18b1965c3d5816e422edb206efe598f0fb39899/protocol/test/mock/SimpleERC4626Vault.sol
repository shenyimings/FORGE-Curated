// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { ERC20 } from '@oz/token/ERC20/ERC20.sol';
import { ERC4626 } from '@oz/token/ERC20/extensions/ERC4626.sol';

contract SimpleERC4626Vault is ERC4626 {
  constructor(address underlying_, string memory name_, string memory symbol_)
    ERC20(name_, symbol_)
    ERC4626(IERC20(underlying_))
  { }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    _burn(from, amount);
  }
}
