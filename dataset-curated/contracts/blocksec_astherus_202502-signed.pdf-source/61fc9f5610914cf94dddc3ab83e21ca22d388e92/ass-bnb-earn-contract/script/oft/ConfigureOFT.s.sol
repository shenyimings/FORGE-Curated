// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { AsBnbOFT } from "../../src/oft/AsBnbOFT.sol";
import { TransferLimiter } from "../../src/oft/TransferLimiter.sol";

contract ConfigureOFTScript is Script {

  uint256 deployerPK;
  address deployer;

  AsBnbOFT asBnbOFT;
  address asBnbOFTAdapter;
  uint32 bscChainEID;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {
    bscChainEID = uint32(vm.envUint("SOURCE_CHAIN_EID"));
    address _asBnbOFT = vm.envAddress("OFT");
    asBnbOFTAdapter = vm.envAddress("OFT_ADAPTER");
    asBnbOFT = AsBnbOFT(_asBnbOFT);
  }

  function run() public {
    // get private key
    deployerPK = vm.envUint("PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    vm.startBroadcast(deployerPK);
    // set peer
    asBnbOFT.setPeer(bscChainEID, bytes32(uint256(uint160(asBnbOFTAdapter))));
    console.log("Peer set for asBnbOFT");
    // setup transfer limits
    setupTransferLimits();
    vm.stopBroadcast();
  }

  // setup transfer limits
  function setupTransferLimits() internal {
    TransferLimiter.TransferLimit[] memory limits = new TransferLimiter.TransferLimit[](1);
    limits[0] = TransferLimiter.TransferLimit(
      bscChainEID,
      type(uint256).max, // max Daily Transfer Amount
      type(uint256).max - 3, // single Transfer Upper Limit
      0.0001 ether, // single Transfer Lower Limit
      type(uint256).max - 2, // daily Transfer Amount Per Address
      type(uint256).max // daily Transfer Attempt Per Address
    );
    asBnbOFT.setTransferLimitConfigs(limits);
    console.log("Transfer limits set");
  }
}
