// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";


import { console } from "forge-std/console.sol";
import {  Broadcaster } from "../src/contracts/Broadcaster.sol";


contract DeployBroadcaster is Script {
    function run() public {
        vm.startBroadcast();
        Broadcaster broadcaster = new Broadcaster();
        vm.stopBroadcast();

        console.log("Broadcaster deployed to:", address(broadcaster));
    }
}