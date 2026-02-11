// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {StreamVault} from "../src/StreamVault.sol";
import {console2} from "forge-std/console2.sol";

contract CheckPeersBaseScript is Script {
    function run() public view {
        // Check Base side
        StreamVault baseVault = StreamVault(0x2B890881268172d1697eB7bc9744F8424E5A3f5a);
        bytes32 arbPeer = baseVault.peers(40231);
        console2.log("Arbitrum peer on Base:", vm.toString(arbPeer));
    }
} 