// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {StreamVault} from "../src/StreamVault.sol";
import {console2} from "forge-std/console2.sol";

contract CheckPeersArbScript is Script {
    function run() public view {
        // Check Arbitrum side
        StreamVault arbVault = StreamVault(0x58107a168E54802A7D35ebDBE6e9f82447d5Fb8d);
        bytes32 basePeer = arbVault.peers(40245);
        console2.log("Base peer on Arbitrum:", vm.toString(basePeer));
    }
} 