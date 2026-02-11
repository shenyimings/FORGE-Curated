// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { MockERC20 } from "../../src/mock/MockERC20.sol";

contract MockERC20Script is Script {
  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    address deployer = msg.sender;
    console.log("Deployer: %s", deployer);
    vm.startBroadcast();
    MockERC20 erc20 = new MockERC20("Staked Lista BNB", "slisBNB");
    vm.stopBroadcast();
    console.log("MockERC20 token address: %s", address(erc20));
  }
}
