// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Whitelist} from "../../src/contracts/Access/Whitelist.sol";

/**
 * @title UpgradeWhitelist
 * @notice Script to upgrade an existing Whitelist proxy to a new implementation
 */
contract UpgradeWhitelist is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("WHITELIST_PROXY_ADDRESS");
        
        console.log("Upgrading Whitelist proxy at:", proxyAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy the new implementation contract
        Whitelist newImplementation = new Whitelist();
        address implementation = address(newImplementation);
        console.log("New Whitelist implementation deployed at:", implementation);
        
        // 2. Upgrade the proxy to the new implementation
        // Cast the proxy address to the Whitelist interface to call upgradeTo
        // Note: Only addresses with ADMIN_ROLE can upgrade the contract
        Whitelist proxy = Whitelist(proxyAddress);
        proxy.upgradeTo(implementation);
        
        console.log("Whitelist proxy upgraded to new implementation");
        
        vm.stopBroadcast();
    }
} 