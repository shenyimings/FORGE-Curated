// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { Buyback } from "../src/Buyback.sol";

contract BuybackImplScript is Script {
  function setUp() public {}

  function run() public {
    address deployer = msg.sender;
    console.log("Deployer: %s", deployer);
    vm.startBroadcast();
    Buyback buyback = new Buyback();
    vm.stopBroadcast();
    console.log("buyback implementation address: %s", address(buyback));
  }
}
