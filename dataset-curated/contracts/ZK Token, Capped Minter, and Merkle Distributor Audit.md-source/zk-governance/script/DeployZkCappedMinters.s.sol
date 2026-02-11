// SPDX-License-Identifier: MIT
// slither-disable-start reentrancy-benign

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {DeployZkCappedMintersInput} from "script/DeployZkCappedMintersInput.sol";
import {ZkCappedMinter} from "src/ZkCappedMinter.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";

contract DeployZkCappedMinters is DeployZkCappedMintersInput, Script {
  uint256 deployerPrivateKey;

  function setUp() public {
    deployerPrivateKey =
      vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
  }

  function run(address tokenAddress) public returns (ZkCappedMinter, ZkCappedMinter) {
    vm.startBroadcast(deployerPrivateKey);
    ZkCappedMinter _associationMinter =
      new ZkCappedMinter(IMintableAndDelegatable(tokenAddress), ASSOCIATION_ADMIN_ACCOUNT, ASSOCIATION_CAP_AMOUNT);
    ZkCappedMinter _foundationMinter =
      new ZkCappedMinter(IMintableAndDelegatable(tokenAddress), FOUNDATION_ADMIN_ACCOUNT, FOUNDATION_CAP_AMOUNT);
    vm.stopBroadcast();

    return (_associationMinter, _foundationMinter);
  }
}
