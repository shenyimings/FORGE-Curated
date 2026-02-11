// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBnbMinter } from "../src/AsBnbMinter.sol";

contract AsBnbMinterImplScript is Script {
  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    uint256 deployerPK = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    vm.startBroadcast(deployerPK);
    AsBnbMinter minter = new AsBnbMinter();
    vm.stopBroadcast();
    console.log("AsBnbMinter implementation address: %s", address(minter));
  }
}
