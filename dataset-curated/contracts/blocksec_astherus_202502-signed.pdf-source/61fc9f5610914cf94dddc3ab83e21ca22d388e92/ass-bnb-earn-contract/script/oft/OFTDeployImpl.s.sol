// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBnbOFT } from "../../src/oft/AsBnbOFT.sol";

contract TargetChainOFTDeploymentImplScript is Script {

  uint256 deployerPK;
  address deployer;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    // get private key
    deployerPK = vm.envUint("PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    // --- endpoints
    address oftLzEndpoint = vm.envAddress("TARGET_LZ_ENDPOINT");

    vm.startBroadcast(deployerPK);
    // deploy impl.
    AsBnbOFT asBnbOFTImpl = new AsBnbOFT(oftLzEndpoint);
    console.log("AsBNBOFTImpl: %s", address(asBnbOFTImpl));
    vm.stopBroadcast();
  }

}
