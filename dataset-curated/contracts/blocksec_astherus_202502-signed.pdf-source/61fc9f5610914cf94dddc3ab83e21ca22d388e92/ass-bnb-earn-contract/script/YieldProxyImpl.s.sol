// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { YieldProxy } from "../src/YieldProxy.sol";

contract YieldProxyImplScript is Script {
  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    uint256 deployerPK = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    vm.startBroadcast(deployerPK);
    YieldProxy yieldProxy = new YieldProxy();
    vm.stopBroadcast();
    console.log("YieldProxy impl. address: %s", address(yieldProxy));
  }
}
