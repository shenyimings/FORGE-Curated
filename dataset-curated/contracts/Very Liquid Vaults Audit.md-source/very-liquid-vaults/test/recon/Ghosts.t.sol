// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Setup} from "@test/recon/Setup.t.sol";

// ghost variables for tracking state variable values before and after function calls
abstract contract Ghosts is Setup {
  struct Vars {
    uint256 __ignore__;
  }

  Vars internal _before;
  Vars internal _after;

  modifier updateGhosts() {
    __before();
    _;
    __after();
  }

  function __before() internal {}

  function __after() internal {}
}
