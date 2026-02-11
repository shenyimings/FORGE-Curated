// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { Minter } from "../src/Minter.sol";

contract MinterImplScript is Script {
  function setUp() public {}

  function run() public {
    address deployer = msg.sender;
    console.log("Deployer: %s", deployer);
    vm.startBroadcast();
    Minter minter = new Minter();
    vm.stopBroadcast();
    console.log("Minter implementation address: %s", address(minter));
  }
}
