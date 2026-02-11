// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBnbOFTAdapter } from "../../src/oft/AsBnbOFTAdapter.sol";
import { TransferLimiter } from "../../src/oft/TransferLimiter.sol";

contract ConfigureOFTScript is Script {

  uint256 deployerPK;
  address deployer;

  AsBnbOFTAdapter asBnbOFTAdapter;
  address asBnbOFT;
  uint32 targetChainEID;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {
    targetChainEID = uint32(vm.envUint("TARGET_CHAIN_EID"));
    asBnbOFT = vm.envAddress("OFT");
    address _asBnbOFTAdapter = vm.envAddress("OFT_ADAPTER");
    asBnbOFTAdapter = AsBnbOFTAdapter(_asBnbOFTAdapter);
  }

  function run() public {
    // get private key
    deployerPK = vm.envUint("PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    vm.startBroadcast(deployerPK);
    // set peer
    asBnbOFTAdapter.setPeer(targetChainEID, bytes32(uint256(uint160(asBnbOFT))));
    console.log("Peer set for asBnbOFTAdapter");
    // setup transfer limits
    setupTransferLimits();
    vm.stopBroadcast();
  }

  // setup transfer limits
  function setupTransferLimits() internal {
    TransferLimiter.TransferLimit[] memory limits = new TransferLimiter.TransferLimit[](1);
    limits[0] = TransferLimiter.TransferLimit(
      targetChainEID,
      type(uint256).max, // max Daily Transfer Amount
      type(uint256).max - 3, // single Transfer Upper Limit
      0.0001 ether, // single Transfer Lower Limit
      type(uint256).max - 2, // daily Transfer Amount Per Address
      type(uint256).max // daily Transfer Attempt Per Address
    );
    asBnbOFTAdapter.setTransferLimitConfigs(limits);
    console.log("Transfer limits set");
  }
}
