// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { MockERC20 } from "../../src/mock/MockERC20.sol";
import { AssToken } from "../../src/AssToken.sol";
import { MockGaugeVoting } from "../../src/mock/pancakeswap/MockGaugeVoting.sol";
import { MockIFO } from "../../src/mock/pancakeswap/MockIFO.sol";
import { MockRevenueSharingPool } from "../../src/mock/pancakeswap/MockRevenueSharingPool.sol";
import { MockRevenueSharingPoolGateway } from "../../src/mock/pancakeswap/MockRevenueSharingPoolGateway.sol";
import { MockCakePlatform } from "../../src/mock/stakeDao/MockCakePlatform.sol";
import { MockVeCake } from "../../src/mock/pancakeswap/MockVeCake.sol";
import { MockPancakeStableSwapPool } from "../../src/mock/pancakeswap/MockPancakeStableSwapPool.sol";
import { MockPancakeStableSwapRouter } from "../../src/mock/pancakeswap/MockPancakeStableSwapRouter.sol";
import "../../src/mock/oneinch/MockAggregationRouterV6.sol";

contract MockThirdPartiesScript is Script {
  function setUp() public {}

  function run() public {
    address deployer = msg.sender;
    console.log("Deployer: %s", deployer);

    // get token address
    address token = vm.envAddress("TOKEN");

    vm.startBroadcast();
    // deploy assToken
    address assTokenPxy = Upgrades.deployUUPSProxy(
      "AssToken.sol",
      abi.encodeCall(AssToken.initialize, ("Astherus CAKE", "asCAKE", deployer, deployer))
    );
    AssToken assToken = AssToken(assTokenPxy);
    // deploy gauge voting
    MockGaugeVoting gaugeVoting = new MockGaugeVoting();
    // deploy ifo
    MockERC20 rewardToken = new MockERC20("LISTA", "Lista Dao");
    MockIFO ifo = new MockIFO(1, address(rewardToken));
    rewardToken.mint(address(ifo), 1000000 ether);
    // deploy pools
    MockRevenueSharingPool pool1 = new MockRevenueSharingPool(address(token));
    MockRevenueSharingPool pool2 = new MockRevenueSharingPool(address(token));
    MockERC20(token).mint(address(pool1), 1000000 ether);
    MockERC20(token).mint(address(pool2), 1000000 ether);
    // deploy pool gateway
    MockRevenueSharingPoolGateway revenueSharingPoolGateway = new MockRevenueSharingPoolGateway();
    // deploy cake platform
    MockCakePlatform cakePlatform = new MockCakePlatform(address(token));
    MockERC20(token).mint(address(pool1), 1000000 ether);
    // deploy veCake
    MockVeCake veCake = new MockVeCake(address(token));
    // deploy pancake stable swap pool
    MockPancakeStableSwapPool pancakeSwapPool = new MockPancakeStableSwapPool(address(token), assTokenPxy, 1e5);
    // deploy pancake stable swap router
    MockPancakeStableSwapRouter pancakeSwapRouter = new MockPancakeStableSwapRouter(address(pancakeSwapPool));

    // deploy one inch router
    address nativeAddress = vm.envAddress("ONE_INCH_SWAP_NATIVE_TOKEN");
    MockAggregationRouterV6 oneInchRouter = new MockAggregationRouterV6(nativeAddress);

    vm.stopBroadcast();
    console.log("MockERC20: %s", address(token));
    console.log("AssToken: %s", address(assToken));
    console.log("MockGaugeVoting: %s", address(gaugeVoting));
    console.log("MockIFO: %s", address(ifo));
    console.log("MockRevenueSharingPool: %s", address(pool1));
    console.log("MockRevenueSharingPool: %s", address(pool2));
    console.log("MockRevenueSharingPoolGateway: %s", address(revenueSharingPoolGateway));
    console.log("MockCakePlatform: %s", address(cakePlatform));
    console.log("MockVeCake: %s", address(veCake));
    console.log("MockPancakeStableSwapPool: %s", address(pancakeSwapPool));
    console.log("MockPancakeStableSwapRouter: %s", address(pancakeSwapRouter));
    console.log("MockAggregationRouterV6: %s", address(oneInchRouter));

  }
}
