// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {BlueprintV5} from "../src/BlueprintV5.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address proxyAddr = vm.envAddress("PROXY_ADDRESS");
        Options memory opts;
        opts.referenceContract = "BlueprintV4.sol";
        Upgrades.upgradeProxy(
            proxyAddr, "BlueprintV5.sol:BlueprintV5", abi.encodeCall(BlueprintV5.initialize, ()), opts
        );
        BlueprintV5 proxy = BlueprintV5(proxyAddr);
        console.log("New Version:", proxy.VERSION());

        vm.stopBroadcast();
    }
}
