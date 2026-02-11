// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Whitelist } from "../../src/contracts/Access/Whitelist.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployWhitelist
 * @notice Deploy script for the Whitelist contract with UUPS proxy pattern
 */
contract DeployWhitelist is Script {
    function run(address admin) public returns (address proxy, address implementation) {
        console.log("Deploying Whitelist contract with admin:", admin);
        
        vm.startBroadcast(admin);
        
        // 1. Deploy the implementation contract
        Whitelist whitelistImpl = new Whitelist();
        implementation = address(whitelistImpl);
        console.log("Whitelist implementation deployed at:", implementation);
        
        // 2. Prepare initialization data for the proxy
        bytes memory initData = abi.encodeWithSelector(
            Whitelist.initialize.selector,
            admin
        );
        
        // 3. Deploy the proxy contract pointing to the implementation
        ERC1967Proxy whitelistProxy = new ERC1967Proxy(
            implementation,
            initData
        );
        proxy = address(whitelistProxy);
        console.log("Whitelist proxy deployed at:", proxy);
        
        // Log deployment success
        console.log("Whitelist deployment complete. Use the proxy address for all interactions.");
        
        vm.stopBroadcast();
        
        return (proxy, implementation);
    }
    
}
