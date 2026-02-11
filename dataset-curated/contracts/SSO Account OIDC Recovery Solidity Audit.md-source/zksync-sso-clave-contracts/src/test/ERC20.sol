// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
  constructor(address mintTo) ERC20("Test ERC20", "TEST") {
    _mint(mintTo, 10 ** 18);
  }
}
