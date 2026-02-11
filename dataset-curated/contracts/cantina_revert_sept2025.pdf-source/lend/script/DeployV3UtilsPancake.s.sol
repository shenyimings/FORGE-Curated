// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/transformers/V3Utils.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract DeployV3UtilsPancake is Script {
    function run() external {
        console.log("Starting deployment script...");
        
        // PancakeSwap addresses on BNB Chain
        address nonfungiblePositionManager = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364; // Pancake NPM
        address universalRouter = 0x1906c1d672b88cD1B9aC7593301cA990F94Eae07; 
        address zeroxAllowanceHolder = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; 
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