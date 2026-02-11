// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { Timelock } from "../src/Timelock.sol";

contract TimelockScript is Script {
  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    uint256 deployerPK = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    address[] memory proposers = new address[](1);
    proposers[0] = deployer;
    address[] memory executors = new address[](1);
    executors[0] = deployer;

    uint256 minDelay = 6 hours;
    uint256 maxDelay = 48 hours;

    vm.startBroadcast(deployerPK);
    Timelock timelock = new Timelock(minDelay, maxDelay, proposers, executors);
    vm.stopBroadcast();
    console.log("Timelock address: %s", address(timelock));
  }
}
