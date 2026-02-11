// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { Buyback } from "../src/Buyback.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BuybackScript is Script {
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
    // swapDstToken
    address swapDstToken = vm.envAddress("ONE_INCH_SWAP_DST_TOKEN");
    require(swapDstToken != address(0), "swapDstToken address cannot be null");
    console.log("swapDstToken: %s", swapDstToken);

    // swap receiver
    address receiver = vm.envAddress("ONE_INCH_SWAP_RECEIVER");
    require(receiver != address(0), "receiver address cannot be null");
    console.log("receiver: %s", receiver);

    // swap oneInchRouter
    address oneInchRouter = vm.envAddress("ONE_INCH_SWAP_ROUTER");
    require(oneInchRouter != address(0), "oneInchRouter address cannot be null");
    console.log("oneInchRouter: %s", oneInchRouter);

    // swap NativeToken
    address swapNativeToken = vm.envAddress("ONE_INCH_SWAP_NATIVE_TOKEN");
    require(swapNativeToken != address(0), "swapNativeToken address cannot be null");
    console.log("swapNativeToken: %s", swapNativeToken);

    vm.startBroadcast(deployerPrivateKey);

    address buybackProxy = Upgrades.deployUUPSProxy(
      "Buyback.sol",
      abi.encodeCall(
        Buyback.initialize,
        (admin, manager, pauser, swapDstToken, receiver, oneInchRouter, swapNativeToken)
      )
    );

    vm.stopBroadcast();
    console.log("Buyback proxy address: %s", buybackProxy);
    address implAddress = Upgrades.getImplementationAddress(buybackProxy);
    console.log("Buyback implementation address: %s", implAddress);
  }
}
