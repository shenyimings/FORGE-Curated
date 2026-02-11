// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { UniversalProxy } from "../src/UniversalProxy.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UniversalProxyScript is Script {
  function setUp() public {}

  function run() public {
    // get private key
    uint256 deployerPK = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    // --- roles
    address admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);

    address pauser = vm.envOr("PAUSER", admin);
    console.log("Pauser: %s", pauser);

    address minter = vm.envOr("MINTER", admin);
    console.log("Minter: %s", minter);

    address manager = vm.envOr("MANAGER", admin);
    console.log("Manager: %s", manager);

    address bot = vm.envOr("BOT", admin);
    console.log("Pauser: %s", bot);

    // --- contract addresses
    // token
    address token = vm.envAddress("TOKEN");
    require(token != address(0), "Token address cannot be null");
    console.log("Token: %s", token);

    // veToken
    address veToken = vm.envAddress("UP_VETOKEN");
    require(veToken != address(0), "veToken address cannot be null");
    console.log("veToken: %s", veToken);

    // gaugeVoting
    address gaugeVoting = vm.envAddress("UP_GAUGE_VOTING");
    require(gaugeVoting != address(0), "gaugeVoting address cannot be null");
    console.log("gaugeVoting: %s", gaugeVoting);

    // ifo
    address ifo = vm.envAddress("UP_IFO");
    require(ifo != address(0), "ifo address cannot be null");
    console.log("ifo: %s", ifo);

    // revenueSharingPools
    address[] memory revenueSharingPools = new address[](2);
    revenueSharingPools[0] = vm.envAddress("UP_REVENUE_SHARING_POOL_1");
    revenueSharingPools[1] = vm.envAddress("UP_REVENUE_SHARING_POOL_2");
    require(revenueSharingPools[0] != address(0), "revenueSharingPool 1 address cannot be null");
    require(revenueSharingPools[1] != address(0), "revenueSharingPool 2 address cannot be null");
    console.log("revenueSharingPools[0]: %s", revenueSharingPools[0]);
    console.log("revenueSharingPools[1]: %s", revenueSharingPools[1]);

    // revenueSharingPoolGateway
    address revenueSharingPoolGateway = vm.envAddress("UP_REVENUE_SHARING_POOL_GATEWAY");
    require(revenueSharingPoolGateway != address(0), "revenueSharingPoolGateway address cannot be null");
    console.log("revenueSharingPoolGateway: %s", revenueSharingPoolGateway);

    // cakePlatform
    address cakePlatform = vm.envAddress("UP_CAKE_PLATFORM");
    require(cakePlatform != address(0), "cakePlatform address cannot be null");
    console.log("cakePlatform: %s", cakePlatform);

    vm.startBroadcast(deployerPK);
    address proxy = Upgrades.deployUUPSProxy(
      "UniversalProxy.sol",
      abi.encodeCall(
        UniversalProxy.initialize,
        (
          admin,
          pauser,
          minter,
          manager,
          bot,
          token,
          veToken,
          gaugeVoting,
          ifo,
          deployer,
          revenueSharingPools,
          revenueSharingPoolGateway,
          cakePlatform
        )
      )
    );
    vm.stopBroadcast();
    console.log("UniversalProxy proxy address: %s", proxy);
    address implAddress = Upgrades.getImplementationAddress(proxy);
    console.log("UniversalProxy implementation address: %s", implAddress);
  }
}
