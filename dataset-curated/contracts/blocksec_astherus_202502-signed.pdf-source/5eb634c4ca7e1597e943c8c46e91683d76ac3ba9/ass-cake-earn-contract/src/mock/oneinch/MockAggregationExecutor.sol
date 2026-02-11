// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./MockAggregationRouterV6.sol";


contract MockAggregationExecutor is IAggregationExecutor {
  // fakes a swap, mints the outToken to the receiver
  function execute(address msgSender) external payable returns (uint256){
    return 0;
  }
}
