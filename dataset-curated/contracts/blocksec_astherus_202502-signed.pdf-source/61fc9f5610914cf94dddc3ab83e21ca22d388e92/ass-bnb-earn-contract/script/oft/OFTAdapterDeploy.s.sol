// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBNB } from "../../src/AsBNB.sol";
import { AsBnbOFT } from "../../src/oft/AsBnbOFT.sol";
import { AsBnbOFTAdapter } from "../../src/oft/AsBnbOFTAdapter.sol";
import { TransferLimiter } from "../../src/oft/TransferLimiter.sol";

import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OFTAdapterDeploymentScript is Script {

  address admin;
  address manager;
  address pauser;
  address token;
  address asBnb;
  uint256 deployerPK;
  address deployer;

  AsBnbOFTAdapter asBnbOFTAdapter;
  uint32 targetChainEID;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
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

    // --- token
    asBnb = vm.envAddress("ASBNB");
    console.log("AsBNB: %s", asBnb);

    // --- endpoints
    address oftAdapterLzEndpoint = vm.envAddress("SRC_LZ_ENDPOINT");

    vm.startBroadcast(deployerPK);

    // deploy impl.
    AsBnbOFTAdapter asBnbOFTAdapterImpl = new AsBnbOFTAdapter(address(asBnb), oftAdapterLzEndpoint);
    console.log("AsBNBOFTAdapterImpl: %s", address(asBnbOFTAdapterImpl));
    // Encode initialization call
    bytes memory asBnbOFTAdapterInitData = abi.encodeWithSignature(
      "initialize(address,address,address,address)",
      admin,
      manager,
      pauser,
      admin // delegate
    );
    // deploy proxy
    ERC1967Proxy asBnbOFTAdapterProxy = new ERC1967Proxy(address(asBnbOFTAdapterImpl), asBnbOFTAdapterInitData);
    asBnbOFTAdapter = AsBnbOFTAdapter(address(asBnbOFTAdapterProxy));
    console.log("AsBNBOFTAdapter: %s", address(asBnbOFTAdapterProxy));

    // set transfer limits
    setupTransferLimits();

    vm.stopBroadcast();
  }

  // setup transfer limits
  function setupTransferLimits() internal {
    targetChainEID = uint32(vm.envUint("TARGET_CHAIN_EID"));
    TransferLimiter.TransferLimit[] memory limits = new TransferLimiter.TransferLimit[](1);
    limits[0] = TransferLimiter.TransferLimit(
      targetChainEID,
      type(uint256).max, // max Daily Transfer Amount
      type(uint256).max - 2, // single Transfer Upper Limit
      0.000001 ether, // single Transfer Lower Limit
      type(uint256).max - 1, // daily Transfer Amount Per Address
      type(uint256).max // daily Transfer Attempt Per Address
    );
    asBnbOFTAdapter.setTransferLimitConfigs(limits);
    console.log("Transfer limits set");
  }
}
