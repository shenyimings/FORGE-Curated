// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBnbOFT } from "../../src/oft/AsBnbOFT.sol";
import { TransferLimiter } from "../../src/oft/TransferLimiter.sol";

import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TargetChainOFTDeploymentScript is Script {

  address admin;
  address manager;
  address pauser;
  address token;
  uint256 deployerPK;
  address deployer;

  AsBnbOFT asBnbOFT;
  uint32 bscChainEID;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {
    // get private key
    deployerPK = vm.envUint("PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    // --- roles
    admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);

    manager = vm.envOr("MANAGER", deployer);
    console.log("Manager: %s", manager);

    pauser = vm.envOr("PAUSER", deployer);
    console.log("Pauser: %s", pauser);
  }

  function run() public {
    vm.startBroadcast(deployerPK);

    address oftLzEndpoint = vm.envAddress("TARGET_LZ_ENDPOINT");
    AsBnbOFT asBnbOFTImpl = new AsBnbOFT(oftLzEndpoint);
    // Encode initialization call
    bytes memory asBnbOFTInitData = abi.encodeWithSignature(
      "initialize(address,address,address,string,string,address)",
      admin,
      manager,
      pauser,
      "Astherus BNB",
      "asBNB",
      admin // delegate (have the right to config oApp at LZ endpoint)
    );
    // deploy proxy
    ERC1967Proxy asBnbOFTProxy = new ERC1967Proxy(address(asBnbOFTImpl), asBnbOFTInitData);
    asBnbOFT = AsBnbOFT(address(asBnbOFTProxy));
    console.log("AsBNBOFT: %s", address(asBnbOFT));

    setupTransferLimits();

    vm.stopBroadcast();
  }

  // setup transfer limits
  function setupTransferLimits() internal {
    bscChainEID = uint32(vm.envUint("SOURCE_CHAIN_EID"));
    TransferLimiter.TransferLimit[] memory limits = new TransferLimiter.TransferLimit[](1);
    limits[0] = TransferLimiter.TransferLimit(
      bscChainEID,
      type(uint256).max, // max Daily Transfer Amount
      type(uint256).max, // single Transfer Upper Limit
      0.0001 ether, // single Transfer Lower Limit
      type(uint256).max, // daily Transfer Amount Per Address
      type(uint256).max // daily Transfer Attempt Per Address
    );
    asBnbOFT.setTransferLimitConfigs(limits);
    console.log("Transfer limits set");
  }
}
