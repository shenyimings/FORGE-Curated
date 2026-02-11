// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {StreamVault} from "../src/StreamVault.sol";

contract CheckBalanceScript is Script {
    function run() public view {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Base Sepolia StreamVault address
        StreamVault vault = StreamVault(0x2B890881268172d1697eB7bc9744F8424E5A3f5a);

        console2.log("Vault balance on Base:", vault.balanceOf(deployer));
    }
}