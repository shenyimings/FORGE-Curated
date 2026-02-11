// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface IReclaimQueueCollector {
  event Collected(address indexed vault, address indexed route, address indexed asset, uint256 collected);
  event RouteSet(address indexed vault, address indexed route);
  event DefaultRouteSet(address indexed route);
  event Withdrawn(address indexed asset, address indexed receiver, uint256 amount);

  function collect(address vault, address asset, uint256 collected) external;
}
