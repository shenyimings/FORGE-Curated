// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/transformers/V3Utils.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract DeployV3UtilsAerodrome is Script {
    function run() external {
        // Hardcoded Aerodrome on Base addresses
        address nonfungiblePositionManager = 0x827922686190790b37229fd06084350E74485b72; // Replace with Aerodrome NPM address
        address universalRouter = 0x6fF5693b99212Da76ad316178A184AB56D299b43;        
        address zeroxAllowanceHolder = 0x0000000000001fF3684f28c67538d4D072C22734;
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Same Permit2 address across chains

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy V3Utils
        V3Utils v3Utils = new V3Utils(
            INonfungiblePositionManager(nonfungiblePositionManager),
            universalRouter,
            zeroxAllowanceHolder,
            permit2
        );

        // Log deployment information
        console.log("V3Utils deployed to:", address(v3Utils));
        console.log("Owner:", v3Utils.owner());

        vm.stopBroadcast();
    }
} 