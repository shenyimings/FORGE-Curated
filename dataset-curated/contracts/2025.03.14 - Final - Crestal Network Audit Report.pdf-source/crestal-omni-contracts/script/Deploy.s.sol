// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {BlueprintV1} from "../src/BlueprintV1.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address proxy =
            Upgrades.deployUUPSProxy("BlueprintV1.sol:BlueprintV1", abi.encodeCall(BlueprintV1.initialize, ()));
        console.log("Deployed proxy:", proxy);
        BlueprintV1 bv1 = BlueprintV1(proxy);
        console.log("Version:", bv1.VERSION());

        vm.stopBroadcast();
    }
}
