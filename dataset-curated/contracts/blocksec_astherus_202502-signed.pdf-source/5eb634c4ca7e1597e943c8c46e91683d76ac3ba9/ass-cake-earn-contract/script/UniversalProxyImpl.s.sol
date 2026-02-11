// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { UniversalProxy } from "../src/UniversalProxy.sol";

contract UniversalProxyImplScript is Script {
  function setUp() public {}

  function run() public {
    address deployer = msg.sender;
    console.log("Deployer: %s", deployer);
    vm.startBroadcast();
    UniversalProxy universalProxy = new UniversalProxy();
    vm.stopBroadcast();
    console.log("UniversalProxy impl. address: %s", address(universalProxy));
  }
}
