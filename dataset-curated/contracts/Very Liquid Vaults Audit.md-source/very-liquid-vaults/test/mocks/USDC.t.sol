// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20MintBurn} from "@test/mocks/IERC20MintBurn.t.sol";

contract USDC is ERC20, IERC20MintBurn, Ownable {
  constructor(address admin) ERC20("USD Coin", "USDC") Ownable(admin) {}

  function decimals() public pure override(ERC20, IERC20Metadata) returns (uint8) {
    return 6;
  }

  function mint(address account, uint256 amount) external onlyOwner {
    _mint(account, amount);
  }

  function burn(address account, uint256 amount) external onlyOwner {
    _burn(account, amount);
  }
}
