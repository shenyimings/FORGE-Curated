// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { PoolTestBase } from "./PoolTestBase.s.sol";

contract AaveFundingPoolTest is PoolTestBase {
  function setUp() external {
    __PoolTestBase_setUp(1.23 ether, 18);
  }

  function testFuzzing() external {}
}
