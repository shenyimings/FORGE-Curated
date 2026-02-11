// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {BlueprintV2} from "../src/BlueprintV2.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address proxyAddr = vm.envAddress("PROXY_ADDRESS");
        Options memory opts;
        opts.referenceContract = "BlueprintV1.sol";
        Upgrades.upgradeProxy(
            proxyAddr, "BlueprintV2.sol:BlueprintV2", abi.encodeCall(BlueprintV2.initialize, ()), opts
        );
        BlueprintV2 proxy = BlueprintV2(proxyAddr);
        console.log("New Version:", proxy.VERSION());

        vm.stopBroadcast();
    }
}
