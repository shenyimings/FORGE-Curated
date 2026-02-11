// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable2Step.sol';

/// @dev Mintable ERC20 token.
contract MintableERC20 is ERC20, Ownable2Step {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
  }
}
