// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Atlas} from "../src/Atlas.sol";

contract AtlasScript is Script {
    Atlas public atlas;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        atlas = new Atlas();

        vm.stopBroadcast();
    }
}
