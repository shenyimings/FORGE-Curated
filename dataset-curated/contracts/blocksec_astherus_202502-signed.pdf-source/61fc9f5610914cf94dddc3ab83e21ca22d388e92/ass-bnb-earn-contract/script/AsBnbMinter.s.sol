// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBnbMinter } from "../src/AsBnbMinter.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract AsBnbMinterScript is Script {
  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: %s", deployer);

    // --- roles
    address admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);

    address manager = vm.envOr("MANAGER", admin);
    console.log("Manager: %s", manager);

    address pauser = vm.envOr("PAUSER", admin);
    console.log("Pauser: %s", pauser);

    address bot = vm.envOr("BOT", admin);
    console.log("Bot: %s", bot);

    // --- contracts
    // token
    address token = vm.envAddress("TOKEN");
    require(token != address(0), "Token address cannot be null");
    console.log("Token: %s", token);

    // AsBnb address
    address asBnb = vm.envAddress("ASBNB");
    require(asBnb != address(0), "AsBnb address cannot be null");
    console.log("AsBnb: %s", asBnb);

    // Yield Proxy
    address yieldProxy = vm.envAddress("YIELD_PROXY");
    require(yieldProxy != address(0), "Yield Proxy address cannot be null");
    console.log("Yield Proxy: %s", yieldProxy);

    vm.startBroadcast(deployerPrivateKey);
    address proxy = Upgrades.deployUUPSProxy(
      "AsBnbMinter.sol",
      abi.encodeCall(AsBnbMinter.initialize, (admin, manager, pauser, bot, token, asBnb, yieldProxy))
    );

    vm.stopBroadcast();
    console.log("AsBnbMinter proxy address: %s", proxy);
    address implAddress = Upgrades.getImplementationAddress(proxy);
    console.log("AsBnbMinter implementation address: %s", implAddress);
  }
}
