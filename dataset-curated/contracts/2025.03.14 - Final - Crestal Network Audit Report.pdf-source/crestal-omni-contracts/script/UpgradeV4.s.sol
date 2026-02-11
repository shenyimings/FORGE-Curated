// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {BlueprintV4} from "../src/BlueprintV4.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address proxyAddr = vm.envAddress("PROXY_ADDRESS");
        Options memory opts;
        opts.referenceContract = "BlueprintV3.sol";
        Upgrades.upgradeProxy(
            proxyAddr, "BlueprintV4.sol:BlueprintV4", abi.encodeCall(BlueprintV4.initialize, ()), opts
        );
        BlueprintV4 proxy = BlueprintV4(proxyAddr);
        console.log("New Version:", proxy.VERSION());

        vm.stopBroadcast();
    }
}
