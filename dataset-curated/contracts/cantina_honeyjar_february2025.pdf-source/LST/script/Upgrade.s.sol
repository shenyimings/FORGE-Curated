// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {fatBERA as FatBERA} from "../src/fatBERA.sol";
import "../src/StakedFatBERAV2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract Upgrade is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        Options memory options;
        options.referenceContract = "StakedFatBERA.sol:StakedFatBERA";
        address deployedAt = Upgrades.deployImplementation("StakedFatBERAV2.sol:StakedFatBERAV2", options);

        console.log("Deployed at", deployedAt);

        vm.stopBroadcast();
    }
}
