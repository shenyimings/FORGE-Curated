// SPDX-License-Identifier: MIT
// slither-disable-start reentrancy-benign

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {DeployZkTokenV1Input} from "script/DeployZkTokenV1Input.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";

contract DeployZkTokenV1 is DeployZkTokenV1Input, Script {
  uint256 deployerPrivateKey;

  function setUp() public {
    deployerPrivateKey =
      vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
  }

  function run() public returns (ZkTokenV1) {
    vm.startBroadcast(deployerPrivateKey);
    address _proxy = Upgrades.deployTransparentProxy(
      "ZkTokenV1.sol",
      ADMIN_ACCOUNT,
      abi.encodeCall(ZkTokenV1.initialize, (ADMIN_ACCOUNT, INITIAL_MINT_ACCOUNT, INITIAL_MINT_AMOUNT))
    );
    vm.stopBroadcast();

    return ZkTokenV1(_proxy);
  }
}
