// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { Minter } from "../src/Minter.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract MinterScript is Script {
  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: %s", deployer);
    address admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);
    address manager = vm.envOr("MANAGER", admin);
    console.log("Manager: %s", manager);
    address pauser = vm.envOr("PAUSER", admin);
    console.log("Pauser: %s", pauser);
    // token
    address token = vm.envAddress("TOKEN");
    require(token != address(0), "Token address cannot be null");
    console.log("Token: %s", token);

    // AssToken address
    address assToken = vm.envAddress("ASSTOKEN");
    require(assToken != address(0), "AssToken address cannot be null");
    console.log("AssToken: %s", assToken);

    // universalProxy address
    address universalProxy = vm.envAddress("UNIVERSAL_PROXY");
    require(universalProxy != address(0), "universalProxy address cannot be null");
    console.log("universalProxy: %s", universalProxy);

    // swap router
    address swapRouter = vm.envAddress("SWAP_ROUTER");
    require(swapRouter != address(0), "Swap router address cannot be null");
    console.log("Swap Router: %s", swapRouter);

    // swap contract
    address smartPool = vm.envAddress("SWAP_POOL");
    require(smartPool != address(0), "Swap pool address cannot be null");
    console.log("Swap Pool: %s", smartPool);

    // max swap ratio
    uint256 maxSwapRatio = vm.envUint("MAX_SWAP_RATIO");

    vm.startBroadcast(deployerPrivateKey);
    address proxy = Upgrades.deployUUPSProxy(
      "Minter.sol",
      abi.encodeCall(
        Minter.initialize,
        (admin, manager, pauser, token, assToken, universalProxy, swapRouter, smartPool, maxSwapRatio)
      )
    );
    vm.stopBroadcast();
    console.log("Minter proxy address: %s", proxy);
    address implAddress = Upgrades.getImplementationAddress(proxy);
    console.log("Minter implementation address: %s", implAddress);
  }
}
