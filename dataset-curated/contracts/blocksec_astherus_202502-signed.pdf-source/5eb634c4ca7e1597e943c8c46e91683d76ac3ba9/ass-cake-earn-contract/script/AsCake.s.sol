// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { AssToken } from "../src/AssToken.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract AsCakeScript is Script {
  function setUp() public {}

  function run() public {
    address deployer = msg.sender;
    console.log("Deployer: %s", deployer);
    vm.startBroadcast();
    address asCAKEProxy = Upgrades.deployUUPSProxy(
      "AssToken.sol",
      abi.encodeCall(
        AssToken.initialize,
        ("Astherus CAKE", "asCAKE", deployer, deployer)
      )
    );
    vm.stopBroadcast();
    console.log("asCAKE address: %s", address(asCAKEProxy));
  }
}
