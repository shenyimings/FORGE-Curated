// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBNB } from "../src/AsBNB.sol";

contract AsBNBScript is Script {
  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    // get private key
    uint256 deployerPK = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    // --- roles
    address admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);

    address minter = vm.envOr("MINTER", admin);
    console.log("Minter: %s", minter);

    vm.startBroadcast(deployerPK);
    address asBNB = address(new AsBNB("Astherus BNB", "asBNB", admin, minter));
    vm.stopBroadcast();

    console.log("AsBNB address: %s", asBNB);
  }
}
